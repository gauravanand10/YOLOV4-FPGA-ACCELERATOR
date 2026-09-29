// Splits a contiguous read (addr, beats of 16 B) into AXI bursts of <= 64 beats that never
// cross a 4 KiB boundary. One command at a time; cmd_ready when idle.
module burst_gen (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        cmd_valid,
  output logic        cmd_ready,
  input  logic [31:0] cmd_addr,     // 16-byte aligned
  input  logic [23:0] cmd_beats,    // > 0
  output logic        ar_valid,
  input  logic        ar_ready,
  output logic [31:0] ar_addr,
  output logic [7:0]  ar_len
);
  logic [31:0] addr;
  logic [23:0] rem;
  logic [8:0]  to4k, blen;

  assign to4k = 9'd256 - {1'b0, addr[11:4]};           // beats to the next 4 KiB page (1..256)
  logic [8:0] m64;
  always_comb begin
    m64  = (rem < 24'd64) ? rem[8:0] : 9'd64;          // min(rem, 64)
    blen = (to4k < m64) ? to4k : m64;                  // min(.., to4k)
  end

  assign cmd_ready = (rem == 0);
  assign ar_valid  = (rem != 0);
  assign ar_addr   = addr;
  assign ar_len    = 8'(blen - 9'd1);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rem <= '0; addr <= '0;
    end else if (rem == 0) begin
      if (cmd_valid) begin addr <= cmd_addr; rem <= cmd_beats; end
    end else if (ar_ready) begin
      addr <= addr + {19'd0, blen, 4'd0};
      rem  <= rem - {15'd0, blen};
    end
  end
endmodule
