// Synchronous FIFO, first-word-fall-through, registers/LUTRAM.
module sync_fifo #(
  parameter int W  = 256,
  parameter int LG = 4
) (
  input  logic         clk,
  input  logic         rst_n,
  input  logic         push,
  input  logic [W-1:0] din,
  input  logic         pop,
  output logic [W-1:0] dout,
  output logic         empty,
  output logic         full,
  output logic [LG:0]  count
);
  (* ram_style = "distributed" *) logic [W-1:0] mem [0:(1<<LG)-1];
  logic [LG-1:0] wp, rp;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wp <= '0; rp <= '0; count <= '0;
    end else begin
      if (push && !full) wp <= wp + 1'b1;
      if (pop && !empty) rp <= rp + 1'b1;
      count <= count + (LG+1)'(push && !full) - (LG+1)'(pop && !empty);
    end
  end
  always_ff @(posedge clk) if (push && !full) mem[wp] <= din;
  assign dout  = mem[rp];
  assign empty = (count == 0);
  assign full  = (count == (1 << LG));
endmodule
