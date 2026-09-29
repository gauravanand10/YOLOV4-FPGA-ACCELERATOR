// AXI4-Lite control/status registers.
//  0x00 CTRL      W: [0] start (self clearing)  RW: [1] irq_en
//  0x04 STATUS    R: [0] busy [1] done          W1C: [1] done (also clears IRQ)
//  0x08 DESC_ADDR RW  descriptor table base (bytes)
//  0x0C NUM_LAYERS RW
//  0x10 CYCLES    R  cycles of current / last run
//  0x14 CUR_LAYER R
//  0x18 ID        R  0x594F4C34
//  0x1C STALL_ROW R  engine cycles stalled waiting for input rows
//  0x20 STALL_OUT R  engine cycles stalled on output credits
//  0x24 WLOAD_CYC R  cycles spent loading weights
module axil_regs (
  input  logic        clk,
  input  logic        rst_n,
  // AXI-Lite slave
  input  logic [7:0]  s_awaddr,
  input  logic        s_awvalid,
  output logic        s_awready,
  input  logic [31:0] s_wdata,
  input  logic [3:0]  s_wstrb,
  input  logic        s_wvalid,
  output logic        s_wready,
  output logic [1:0]  s_bresp,
  output logic        s_bvalid,
  input  logic        s_bready,
  input  logic [7:0]  s_araddr,
  input  logic        s_arvalid,
  output logic        s_arready,
  output logic [31:0] s_rdata,
  output logic [1:0]  s_rresp,
  output logic        s_rvalid,
  input  logic        s_rready,
  // core
  output logic        start,
  output logic [31:0] desc_addr,
  output logic [15:0] num_layers,
  input  logic        busy,
  input  logic        done_pulse,
  input  logic [31:0] cycles,
  input  logic [15:0] cur_layer,
  input  logic [31:0] stall_row,
  input  logic [31:0] stall_out,
  input  logic [31:0] wload_cyc,
  output logic        irq
);
  logic irq_en, done;
  logic [7:0] awaddr_q;
  logic aw_got, w_got;
  logic [31:0] wdata_q;

  // write channel: accept AW and W independently, respond when both seen
  assign s_awready = !aw_got && !s_bvalid;
  assign s_wready  = !w_got && !s_bvalid;
  assign s_bresp   = 2'b00;
  assign s_rresp   = 2'b00;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      aw_got <= 1'b0; w_got <= 1'b0; s_bvalid <= 1'b0;
      awaddr_q <= '0; wdata_q <= '0;
      irq_en <= 1'b0; done <= 1'b0; start <= 1'b0;
      desc_addr <= '0; num_layers <= '0;
    end else begin
      start <= 1'b0;
      if (done_pulse) done <= 1'b1;
      if (s_awvalid && s_awready) begin aw_got <= 1'b1; awaddr_q <= s_awaddr; end
      if (s_wvalid && s_wready)   begin w_got  <= 1'b1; wdata_q  <= s_wdata;  end
      if (aw_got && w_got) begin
        aw_got <= 1'b0; w_got <= 1'b0; s_bvalid <= 1'b1;
        case (awaddr_q[7:2])
          6'h00: begin
            irq_en <= wdata_q[1];
            if (wdata_q[0] && !busy) begin start <= 1'b1; done <= 1'b0; end
          end
          6'h01: if (wdata_q[1]) done <= 1'b0;
          6'h02: desc_addr  <= wdata_q;
          6'h03: num_layers <= wdata_q[15:0];
          default: ;
        endcase
      end
      if (s_bvalid && s_bready) s_bvalid <= 1'b0;
    end
  end

  // read channel
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      s_rvalid <= 1'b0; s_rdata <= '0; s_arready <= 1'b0;
    end else begin
      s_arready <= !s_rvalid && !s_arready;
      if (s_arvalid && s_arready) begin
        s_rvalid <= 1'b1;
        case (s_araddr[7:2])
          6'h00: s_rdata <= {30'd0, irq_en, 1'b0};
          6'h01: s_rdata <= {30'd0, done, busy};
          6'h02: s_rdata <= desc_addr;
          6'h03: s_rdata <= {16'd0, num_layers};
          6'h04: s_rdata <= cycles;
          6'h05: s_rdata <= {16'd0, cur_layer};
          6'h06: s_rdata <= yolo_pkg::ACCEL_ID;
          6'h07: s_rdata <= stall_row;
          6'h08: s_rdata <= stall_out;
          6'h09: s_rdata <= wload_cyc;
          default: s_rdata <= 32'hDEAD_BEEF;
        endcase
      end
      if (s_rvalid && s_rready) s_rvalid <= 1'b0;
    end
  end

  assign irq = done & irq_en;
endmodule
