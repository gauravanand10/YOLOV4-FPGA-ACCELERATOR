// Simple dual-port RAM: one write port, one read port, registered read.
// LAT = 1: q valid 1 cycle after raddr; LAT = 2: extra output register (BRAM DOB_REG).
module sdp_ram #(
  parameter int W   = 128,
  parameter int LG  = 10,
  parameter int LAT = 2
) (
  input  logic          clk,
  input  logic          we,
  input  logic [LG-1:0] waddr,
  input  logic [W-1:0]  wdata,
  input  logic [LG-1:0] raddr,
  output logic [W-1:0]  q
);
  (* ram_style = "block" *) logic [W-1:0] mem [0:(1<<LG)-1];
  logic [W-1:0] q0;
  always_ff @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
    q0 <= mem[raddr];
  end
  if (LAT == 2) begin : g_oreg
    always_ff @(posedge clk) q <= q0;
  end else begin : g_noreg
    assign q = q0;
  end
endmodule
