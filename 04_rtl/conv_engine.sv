// Convolution engine for one 32-output-channel group.
//   loop: oy, ox, ky, kx, c  -> one (tap, cin_chunk) per cycle into the 32x16 PE array
//   line buffer: 8 slots x 1024 x 128b (slot = iy % 8, addr = ix*cc + c)
//   weight buffer: 32 banks x 512 x 128b (addr = tap*cc + c)
// A pixel is started only when its input rows are loaded and an output-FIFO credit is free,
// so the pipeline behind the issue stage never stalls.
module conv_engine import yolo_pkg::*; (
  input  logic          clk,
  input  logic          rst_n,
  input  logic          start,          // pulse: begin group (config stable)
  input  logic [15:0]   in_wc, in_hc, out_w, out_h,
  input  logic [7:0]    cc,
  input  logic [3:0]    k, s, pad,
  input  logic [15:0]   kkcc,
  output logic          issue_done,     // all pixels issued
  output logic signed [17:0] row_limit, // loader may fetch rows < row_limit
  input  logic [15:0]   rows_done,
  // weight loader write ports
  input  logic          prm_we,
  input  logic [4:0]    prm_idx,
  input  logic [127:0]  prm_data,
  input  logic          wb_we,
  input  logic [4:0]    wb_bank,
  input  logic [8:0]    wb_addr,
  input  logic [127:0]  wb_data,
  // line loader write port
  input  logic          lb_we,
  input  logic [12:0]   lb_waddr,
  input  logic [127:0]  lb_wdata,
  // output pixels (32 channels) to writer
  output logic [255:0]  of_dout,
  output logic          of_empty,
  input  logic          of_pop,
  output logic [OFIFO_LG:0] credits,
  // stats
  output logic          stall_row,
  output logic          stall_out
);

  // ---------------- parameters ----------------
  logic [127:0] prm [0:31];
  always_ff @(posedge clk) if (prm_we) prm[prm_idx] <= prm_data;

  // ---------------- issue stage ----------------
  logic        busy;
  logic [15:0] oy, ox, wa;
  logic [3:0]  ky, kx;
  logic [7:0]  c;
  logic signed [17:0] row_min, col_min;
  logic signed [17:0] need_rows;
  logic        pix_ok, fire;
  logic [OFIFO_LG:0] cred;

  always_comb begin
    need_rows = row_min + $signed({14'd0, k});
    if (need_rows > $signed({2'b00, in_hc})) need_rows = $signed({2'b00, in_hc});
  end
  wire rows_ok = $signed({2'b00, rows_done}) >= need_rows;
  wire cred_ok = cred < (OFIFO_LG+1)'(1 << OFIFO_LG);
  assign pix_ok = rows_ok && cred_ok;
  wire  pix_start = busy && (wa == 0);
  assign fire  = busy && (wa != 0 || pix_ok);
  wire  last_tap = (wa == kkcc - 1'b1);
  wire  pix_fire = fire && (wa == 0);
  assign stall_row = pix_start && !rows_ok;
  assign stall_out = pix_start && rows_ok && !cred_ok;

  // S0 outputs
  logic        s0_v, s0_first, s0_last;
  logic signed [17:0] s0_iy, s0_ix;
  logic [7:0]  s0_c;
  logic [8:0]  s0_wa;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      busy <= 1'b0; issue_done <= 1'b0;
      oy <= '0; ox <= '0; wa <= '0; ky <= '0; kx <= '0; c <= '0;
      row_min <= '0; col_min <= '0;
      s0_v <= 1'b0;
    end else if (start) begin
      busy <= 1'b1; issue_done <= 1'b0;
      oy <= '0; ox <= '0; wa <= '0; ky <= '0; kx <= '0; c <= '0;
      row_min <= -$signed({14'd0, pad}); col_min <= -$signed({14'd0, pad});
      s0_v <= 1'b0;
    end else begin
      s0_v <= fire;
      if (fire) begin
        s0_first <= (wa == 0);
        s0_last  <= last_tap;
        s0_iy    <= row_min + $signed({14'd0, ky});
        s0_ix    <= col_min + $signed({14'd0, kx});
        s0_c     <= c;
        s0_wa    <= wa[8:0];
        // advance c -> kx -> ky -> pixel
        if (c != cc - 1'b1) c <= c + 1'b1;
        else begin
          c <= '0;
          if (kx != k - 1'b1) kx <= kx + 1'b1;
          else begin
            kx <= '0;
            if (ky != k - 1'b1) ky <= ky + 1'b1;
            else ky <= '0;
          end
        end
        if (!last_tap) wa <= wa + 1'b1;
        else begin
          wa <= '0;
          if (ox != out_w - 1'b1) begin
            ox <= ox + 1'b1; col_min <= col_min + $signed({14'd0, s});
          end else begin
            ox <= '0; col_min <= -$signed({14'd0, pad});
            row_min <= row_min + $signed({14'd0, s});
            if (oy != out_h - 1'b1) oy <= oy + 1'b1;
            else begin oy <= '0; busy <= 1'b0; issue_done <= 1'b1; end
          end
        end
      end
    end
  end

  // loader permission, delayed so in-flight line-buffer reads of the old top row complete
  logic signed [17:0] rl_d [0:3];
  always_ff @(posedge clk) begin
    if (start) begin
      for (int i = 0; i < 4; i++) rl_d[i] <= 18'sd8 - $signed({14'd0, pad});
    end else begin
      rl_d[0] <= busy ? row_min + 18'sd8 : 18'sh1FFFF;   // idle after last row: no limit
      for (int i = 1; i < 4; i++) rl_d[i] <= rl_d[i-1];
    end
  end
  assign row_limit = rl_d[3];

  // ---------------- S1: addresses ----------------
  logic        s1_v, s1_first, s1_last, s1_inb;
  logic [12:0] s1_lba;
  logic [8:0]  s1_wa;
  wire s0_inb = (s0_iy >= 0) && (s0_iy < $signed({2'b00, in_hc})) &&
                (s0_ix >= 0) && (s0_ix < $signed({2'b00, in_wc}));
  wire [15:0] s0_xoff = s0_ix[9:0] * cc;
  always_ff @(posedge clk) begin
    s1_v     <= s0_v && rst_n;
    s1_first <= s0_first;
    s1_last  <= s0_last;
    s1_inb   <= s0_inb;
    s1_lba   <= {s0_iy[2:0], s0_xoff[9:0] + {2'b00, s0_c}};
    s1_wa    <= s0_wa;
  end

  // ---------------- buffers (2-cycle read) ----------------
  logic [127:0] lb_q;
  logic [127:0] wb_q [0:31];
  sdp_ram #(.W(128), .LG(13), .LAT(2)) u_lb (
    .clk, .we(lb_we), .waddr(lb_waddr), .wdata(lb_wdata), .raddr(s1_lba), .q(lb_q));
  for (genvar o = 0; o < 32; o++) begin : g_wb
    sdp_ram #(.W(128), .LG(9), .LAT(2)) u_wb (
      .clk, .we(wb_we && wb_bank == o), .waddr(wb_addr), .wdata(wb_data), .raddr(s1_wa), .q(wb_q[o]));
  end

  logic [2:0] p_v, p_first, p_last, p_inb;
  always_ff @(posedge clk) begin
    p_v     <= {p_v[1:0], s1_v && rst_n};
    p_first <= {p_first[1:0], s1_first};
    p_last  <= {p_last[1:0], s1_last};
    p_inb   <= {p_inb[1:0], s1_inb};
  end
  // p_*[1] aligns with lb_q / wb_q (2 cycles after S1)
  wire [127:0] xin = p_inb[1] ? lb_q : 128'd0;

  // ---------------- PE array (3 cycles) ----------------
  logic signed [19:0] psum [0:31];
  pe_array u_pe (.clk, .x(xin), .w(wb_q), .sum(psum));
  logic [2:0] q_v, q_first, q_last;
  always_ff @(posedge clk) begin
    q_v     <= {q_v[1:0], p_v[1] && rst_n};
    q_first <= {q_first[1:0], p_first[1]};
    q_last  <= {q_last[1:0], p_last[1]};
  end

  // ---------------- accumulate ----------------
  logic signed [31:0] acc [0:31];
  logic signed [31:0] acc_out [0:31];
  logic               acc_ov;
  always_ff @(posedge clk) begin
    acc_ov <= q_v[2] && q_last[2] && rst_n;
    for (int o = 0; o < 32; o++) begin
      if (q_v[2]) begin
        acc[o] <= q_first[2] ? 32'(psum[o]) : acc[o] + 32'(psum[o]);
        if (q_last[2]) acc_out[o] <= q_first[2] ? 32'(psum[o]) : acc[o] + 32'(psum[o]);
      end
    end
  end

  // ---------------- epilogue + output FIFO ----------------
  logic         ep_v;
  logic [255:0] ep_y;
  epilogue u_ep (.clk, .in_valid(acc_ov), .acc(acc_out), .prm(prm), .out_valid(ep_v), .y(ep_y));

  logic of_full;
  logic [OFIFO_LG:0] of_cnt;
  sync_fifo #(.W(256), .LG(OFIFO_LG)) u_of (
    .clk, .rst_n, .push(ep_v), .din(ep_y), .pop(of_pop), .dout(of_dout),
    .empty(of_empty), .full(of_full), .count(of_cnt));

  // credits = pixels issued but not yet popped by the writer
  always_ff @(posedge clk) begin
    if (!rst_n) cred <= '0;
    else cred <= cred + (OFIFO_LG+1)'(pix_fire) - (OFIFO_LG+1)'(of_pop && !of_empty);
  end
  assign credits = cred;

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n && ep_v && of_full) $error("conv_engine: output FIFO overflow");
`endif
endmodule
