// Output writer: pops 32-channel pixels from the engine FIFO and writes 32-byte bursts (2 beats)
// to up to two destinations; with ups=1 each pixel is replicated to a 2x2 block (nearest upsample).
// Addresses are generated incrementally (no multipliers in the per-pixel path).
// AW and W of a burst are issued concurrently; the burst completes when both are done.
module writer (
  input  logic          clk,
  input  logic          rst_n,
  input  logic          start,          // pulse per group, config stable
  input  logic [31:0]   addr0, addr1,   // dest bases incl. channel offset (group offset added here)
  input  logic [15:0]   ps0, ps1,       // pixel strides (bytes)
  input  logic          en1, ups,
  input  logic [15:0]   out_w,          // conv output width (pre-upsample)
  input  logic [7:0]    grp,
  output logic          idle,           // no pixel in progress
  // FIFO
  input  logic [255:0]  of_dout,
  input  logic          of_empty,
  output logic          of_pop,
  // AXI write
  output logic          aw_valid,
  input  logic          aw_ready,
  output logic [31:0]   aw_addr,
  output logic [7:0]    aw_len,
  output logic          w_valid,
  input  logic          w_ready,
  output logic [127:0]  w_data,
  output logic          w_last,
  input  logic          b_valid,
  output logic [15:0]   outstanding
);
  logic [31:0] pix0, pix1, rowp0, rowp1;      // current pixel / row start address per destination
  logic [31:0] rowb0, rowb1, step0, step1, pitch0, pitch1;
  logic [15:0] ox;
  logic [255:0] data;
  logic        busy, aw_sent, w_done, wb;
  logic        d;              // current destination
  logic [1:0]  sp;             // upsample sub-position {dy, dx}

  // constant per layer: destination row pitch (in destination pixels), per-pixel step, per-row step
  wire [16:0] dst_w = ups ? {out_w, 1'b0} : {1'b0, out_w};
  always_ff @(posedge clk) begin
    rowb0  <= dst_w * ps0;
    rowb1  <= dst_w * ps1;
    step0  <= ups ? {15'd0, ps0, 1'b0} : {16'd0, ps0};
    step1  <= ups ? {15'd0, ps1, 1'b0} : {16'd0, ps1};
    pitch0 <= ups ? {rowb0[30:0], 1'b0} : rowb0;
    pitch1 <= ups ? {rowb1[30:0], 1'b0} : rowb1;
  end

  wire [31:0] pb  = d ? pix1 : pix0;
  wire [31:0] rb  = d ? rowb1 : rowb0;
  wire [15:0] psd = d ? ps1 : ps0;
  assign aw_addr  = pb + (sp[1] ? rb : 32'd0) + (sp[0] ? {16'd0, psd} : 32'd0);
  assign aw_len   = 8'd1;
  assign aw_valid = busy && !aw_sent;
  assign w_valid  = busy && !w_done;
  assign w_data   = wb ? data[255:128] : data[127:0];
  assign w_last   = wb;
  assign idle     = !busy;

  wire aw_fire  = aw_valid && aw_ready;
  wire w_fire   = w_valid && w_ready;
  wire burst_ok = busy && (aw_sent || aw_fire) && (w_done || (w_fire && wb));
  wire last_sp  = ups ? (sp == 2'b11) : 1'b1;
  wire last_d   = en1 ? d : 1'b1;
  wire pix_ok   = burst_ok && last_sp && last_d;
  assign of_pop = (!busy || pix_ok) && !of_empty && !start;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      busy <= 1'b0; aw_sent <= 1'b0; w_done <= 1'b0; wb <= 1'b0; d <= 1'b0; sp <= '0; ox <= '0;
      outstanding <= '0; data <= '0;
      pix0 <= '0; pix1 <= '0; rowp0 <= '0; rowp1 <= '0;
    end else begin
      outstanding <= outstanding + 16'(aw_fire) - 16'(b_valid);
      if (start) begin
        pix0  <= addr0 + {19'd0, grp, 5'd0};
        pix1  <= addr1 + {19'd0, grp, 5'd0};
        rowp0 <= addr0 + {19'd0, grp, 5'd0};
        rowp1 <= addr1 + {19'd0, grp, 5'd0};
        ox <= '0;
      end else begin
        if (aw_fire) aw_sent <= 1'b1;
        if (w_fire) begin
          wb <= ~wb;
          if (wb) w_done <= 1'b1;
        end
        if (burst_ok) begin
          aw_sent <= 1'b0; w_done <= 1'b0; wb <= 1'b0;
          if (!last_sp) sp <= sp + 1'b1;
          else begin
            sp <= '0;
            d  <= last_d ? 1'b0 : 1'b1;
          end
        end
        if (pix_ok) begin
          busy <= 1'b0;
          if (ox == out_w - 1'b1) begin
            ox <= '0;
            pix0 <= rowp0 + pitch0; rowp0 <= rowp0 + pitch0;
            pix1 <= rowp1 + pitch1; rowp1 <= rowp1 + pitch1;
          end else begin
            ox <= ox + 1'b1;
            pix0 <= pix0 + step0;
            pix1 <= pix1 + step1;
          end
        end
        if (of_pop) begin
          data <= of_dout; busy <= 1'b1;
        end
      end
    end
  end
endmodule
