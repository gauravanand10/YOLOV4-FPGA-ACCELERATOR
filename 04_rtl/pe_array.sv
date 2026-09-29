// 32 x 16 INT8 PE array: lane o computes dot(x[16], w[o][16]) through a pipelined adder tree.
// Latency: 3 cycles (product reg, 16->4 reg, 4->1 reg).
module pe_array (
  input  logic          clk,
  input  logic [127:0]  x,            // 16 x int8 activations
  input  logic [127:0]  w [0:31],     // per lane 16 x int8 weights
  output logic signed [19:0] sum [0:31]
);
  for (genvar o = 0; o < 32; o++) begin : g_lane
    logic signed [15:0] p  [0:15];
    logic signed [17:0] s4 [0:3];
    for (genvar i = 0; i < 16; i++) begin : g_mul
      always_ff @(posedge clk)
        p[i] <= $signed(x[8*i +: 8]) * $signed(w[o][8*i +: 8]);
    end
    for (genvar j = 0; j < 4; j++) begin : g_s4
      always_ff @(posedge clk)
        s4[j] <= 18'(p[4*j]) + 18'(p[4*j+1]) + 18'(p[4*j+2]) + 18'(p[4*j+3]);
    end
    always_ff @(posedge clk)
      sum[o] <= 20'(s4[0]) + 20'(s4[1]) + 20'(s4[2]) + 20'(s4[3]);
  end
endmodule
