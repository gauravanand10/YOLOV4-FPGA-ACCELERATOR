// Line loader: streams conv-input rows r = 0..in_hc-1 from DDR into the 8-slot line buffer
// (slot = r % 8, addr = slot*1024 + x*cc + c). With pool=1 each conv row is the 2x2/s2 max of
// stored rows 2r, 2r+1 (horizontal max via hreg[c], vertical max via the pool-row buffer).
// A row r is only fetched when r < row_limit (engine: current top row + 8).
module line_loader (
  input  logic         clk,
  input  logic         rst_n,
  input  logic         start,
  input  logic [31:0]  in_addr,
  input  logic [15:0]  in_w,        // stored width
  input  logic [15:0]  in_ps,       // pixel stride (bytes)
  input  logic [7:0]   cc,
  input  logic         pool,
  input  logic [15:0]  in_hc,       // conv rows
  input  logic signed [17:0] row_limit,
  output logic [15:0]  rows_done,
  output logic         done,
  // AXI read (via mux)
  output logic         ar_valid,
  input  logic         ar_ready,
  output logic [31:0]  ar_addr,
  output logic [7:0]   ar_len,
  input  logic         r_valid,
  input  logic [127:0] r_data,
  // line buffer write port
  output logic         lb_we,
  output logic [12:0]  lb_waddr,
  output logic [127:0] lb_wdata
);
  import yolo_pkg::*;

  // ---------------- request side ----------------
  logic [31:0] row_bytes, row_addr, px_addr;
  logic [23:0] row_beats;
  logic        contig;
  logic [15:0] r, x;
  logic        sub;
  typedef enum logic [1:0] {Q_IDLE, Q_ROW, Q_CMD} qst_t;
  qst_t qst;
  logic        cmd_valid, cmd_ready;
  logic [31:0] cmd_addr;
  logic [23:0] cmd_beats;

  always_ff @(posedge clk) begin
    row_bytes <= in_w * in_ps;
    row_beats <= in_w * cc;
    contig    <= ({in_ps[15:4], 4'd0} == in_ps) && (in_ps[15:4] == {4'd0, cc});
  end

  assign cmd_valid = (qst == Q_CMD);
  assign cmd_addr  = contig ? row_addr : px_addr;
  assign cmd_beats = contig ? row_beats : {16'd0, cc};

  burst_gen u_bg (
    .clk, .rst_n, .cmd_valid, .cmd_ready, .cmd_addr, .cmd_beats,
    .ar_valid, .ar_ready, .ar_addr, .ar_len);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      qst <= Q_IDLE; r <= '0; x <= '0; sub <= 1'b0; row_addr <= '0; px_addr <= '0;
    end else if (start) begin
      qst <= Q_ROW; r <= '0; x <= '0; sub <= 1'b0; row_addr <= in_addr; px_addr <= in_addr;
    end else begin
      case (qst)
        Q_ROW: begin
          if (r == in_hc) qst <= Q_IDLE;
          else if ($signed({2'b00, r}) < row_limit) begin
            qst <= Q_CMD; x <= '0; px_addr <= row_addr;
          end
        end
        Q_CMD: if (cmd_ready) begin
          if (!contig && x != in_w - 1'b1) begin
            x <= x + 1'b1;
            px_addr <= px_addr + {16'd0, in_ps};
          end else begin
            // input row finished
            row_addr <= row_addr + row_bytes;
            px_addr  <= row_addr + row_bytes;
            x <= '0;
            if (pool && !sub) begin
              sub <= 1'b1;            // second stored row of the same conv row
            end else begin
              sub <= 1'b0; r <= r + 1'b1; qst <= Q_ROW;
            end
          end
        end
        default: ;
      endcase
    end
  end

  // ---------------- data side ----------------
  logic [15:0] rr, rx;
  logic [7:0]  rc;
  logic        rsub;
  logic [9:0]  ptr;
  logic [127:0] hreg [0:31];
  logic [127:0] hm;
  // stage A -> B
  logic        a_we, a_vmax, a_rowend;
  logic [12:0] a_addr;
  logic [127:0] a_data;
  logic        prb_we;
  logic [127:0] prb_q;

  assign hm = vmax8(hreg[rc[4:0]], r_data);

  sdp_ram #(.W(128), .LG(10), .LAT(1)) u_prb (
    .clk, .we(prb_we), .waddr(ptr), .wdata(hm), .raddr(ptr), .q(prb_q));

  wire last_px   = (rx == in_w - 1'b1) && (rc == cc - 1'b1);
  wire odd_px    = rx[0];
  assign prb_we  = r_valid && pool && !rsub && odd_px;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rr <= '0; rx <= '0; rc <= '0; rsub <= 1'b0; ptr <= '0;
      a_we <= 1'b0; a_vmax <= 1'b0; a_rowend <= 1'b0; a_addr <= '0; a_data <= '0;
      lb_we <= 1'b0; lb_waddr <= '0; lb_wdata <= '0; rows_done <= '0;
    end else begin
      // stage B: line buffer write
      lb_we    <= a_we;
      lb_waddr <= a_addr;
      lb_wdata <= a_vmax ? vmax8(a_data, prb_q) : a_data;
      if (a_rowend) rows_done <= rows_done + 1'b1;
      // stage A
      a_we <= 1'b0; a_rowend <= 1'b0; a_vmax <= 1'b0;
      if (start) begin
        rr <= '0; rx <= '0; rc <= '0; rsub <= 1'b0; ptr <= '0; rows_done <= '0;
      end else if (r_valid) begin
        if (!pool) begin
          a_we <= 1'b1; a_addr <= {rr[2:0], ptr}; a_data <= r_data;
          ptr <= ptr + 1'b1;
        end else if (!odd_px) begin
          hreg[rc[4:0]] <= r_data;
        end else begin
          ptr <= ptr + 1'b1;
          if (rsub) begin
            a_we <= 1'b1; a_vmax <= 1'b1; a_addr <= {rr[2:0], ptr}; a_data <= hm;
          end
        end
        // counters
        if (rc == cc - 1'b1) begin
          rc <= '0;
          rx <= (rx == in_w - 1'b1) ? 16'd0 : rx + 1'b1;
        end else begin
          rc <= rc + 1'b1;
        end
        if (last_px) begin
          ptr <= '0;
          if (pool && !rsub) rsub <= 1'b1;
          else begin rsub <= 1'b0; rr <= rr + 1'b1; a_rowend <= 1'b1; end
        end
      end
    end
  end

  assign done = (qst == Q_IDLE) && (rows_done == in_hc) && !a_we && !lb_we;
endmodule
