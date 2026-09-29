// AXI4 slave memory model (128-bit) for the accelerator testbench.
//  - in-order read data with configurable latency and random R/AR/AW/W throttling
//  - protocol checks: INCR, 16-byte size, len <= 63, no 4 KiB crossing, WLAST position, in-range
//  - memory: words[(addr - BASE) >> 4]
module axi_mem_model #(
  parameter int WORDS_LG = 20
) (
  input  logic          clk,
  input  logic          rst_n,
  input  logic [31:0]   base,
  input  int            rd_lat,        // cycles AR -> first R beat
  input  int            stall_pct,     // 0..100 random de-assertion of ready/valid
  // AW
  input  logic [31:0]   awaddr,
  input  logic [7:0]    awlen,
  input  logic [2:0]    awsize,
  input  logic [1:0]    awburst,
  input  logic          awvalid,
  output logic          awready,
  // W
  input  logic [127:0]  wdata,
  input  logic [15:0]   wstrb,
  input  logic          wlast,
  input  logic          wvalid,
  output logic          wready,
  // B
  output logic [1:0]    bresp,
  output logic          bvalid,
  input  logic          bready,
  // AR
  input  logic [31:0]   araddr,
  input  logic [7:0]    arlen,
  input  logic [2:0]    arsize,
  input  logic [1:0]    arburst,
  input  logic          arvalid,
  output logic          arready,
  // R
  output logic [127:0]  rdata,
  output logic [1:0]    rresp,
  output logic          rlast,
  output logic          rvalid,
  input  logic          rready
);
  bit [127:0] mem [0:(1<<WORDS_LG)-1];
  int unsigned errors = 0;
  longint unsigned cyc = 0;
  longint unsigned rd_beats = 0, wr_beats = 0, rd_bursts = 0, wr_bursts = 0;

  typedef struct { logic [31:0] addr; int len; longint unsigned t; } req_t;
  req_t arq[$];
  req_t awq[$];
  longint unsigned bq[$];

  function automatic int idx(input logic [31:0] a);
    return int'((a - base) >> 4);
  endfunction

  task automatic check_burst(input string ch, input logic [31:0] a, input logic [7:0] len,
                             input logic [2:0] size, input logic [1:0] burst);
    if (burst != 2'b01 || size != 3'd4 || a[3:0] != 0 || len > 8'd63 ||
        (a[11:0] + (int'(len) + 1) * 16) > 4096 ||
        a < base || idx(a) + int'(len) >= (1 << WORDS_LG)) begin
      errors++;
      if (errors < 20)
        $error("AXI %s protocol/range violation addr=%h len=%0d size=%0d burst=%0d", ch, a, len, size, burst);
    end
  endtask

  function automatic bit coin();
    return ($urandom_range(99) < stall_pct);
  endfunction

  // ---------------- read ----------------
  int rbeat;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      arready <= 1'b0; rvalid <= 1'b0; rlast <= 1'b0; rbeat = 0; arq.delete();
    end else begin
      cyc <= cyc + 1;
      if (arvalid && arready) begin
        check_burst("AR", araddr, arlen, arsize, arburst);
        arq.push_back('{araddr, int'(arlen) + 1, cyc + longint'(rd_lat)});
        rd_bursts++;
      end
      arready <= !coin() && arq.size() < 16;
      if (rvalid && rready) begin
        rd_beats++;
        if (rlast) begin void'(arq.pop_front()); rbeat = 0; end
        else rbeat++;
      end
      if (!rvalid || rready) begin
        rvalid <= 1'b0; rlast <= 1'b0;
        if (arq.size() > 0 && arq[0].t <= cyc && !coin()) begin
          rvalid <= 1'b1;
          rdata  <= mem[idx(arq[0].addr) + rbeat];
          rlast  <= (rbeat == arq[0].len - 1);
        end
      end
    end
  end
  assign rresp = 2'b00;

  // ---------------- write ----------------
  int wbeat;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      awready <= 1'b0; wready <= 1'b0; bvalid <= 1'b0; wbeat = 0; awq.delete(); bq.delete();
    end else begin
      if (awvalid && awready) begin
        check_burst("AW", awaddr, awlen, awsize, awburst);
        awq.push_back('{awaddr, int'(awlen) + 1, 0});
        wr_bursts++;
      end
      if (wvalid && wready) begin
        if (awq.size() == 0) begin errors++; $error("W beat without AW"); end
        else begin
          int i;
          i = idx(awq[0].addr) + wbeat;
          for (int b = 0; b < 16; b++) if (wstrb[b]) mem[i][8*b +: 8] = wdata[8*b +: 8];
          wr_beats++;
          if (wlast != (wbeat == awq[0].len - 1)) begin errors++; $error("WLAST mismatch"); end
          if (wbeat == awq[0].len - 1) begin
            void'(awq.pop_front()); wbeat = 0;
            bq.push_back(cyc + 8 + $urandom_range(8));
          end else wbeat++;
        end
      end
      awready <= !coin() && awq.size() < 8;
      wready  <= !coin() && awq.size() > 0;     // W accepted only after its AW (legal slave behaviour)
      if (bvalid && bready) bvalid <= 1'b0;
      if ((!bvalid || bready) && bq.size() > 0 && bq[0] <= cyc) begin
        bvalid <= 1'b1; void'(bq.pop_front());
      end
    end
  end
  assign bresp = 2'b00;
endmodule
