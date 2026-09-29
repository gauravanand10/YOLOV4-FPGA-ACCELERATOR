// Per-channel requantisation, 32 lanes in parallel, fully pipelined (5 cycles):
//   t = sat27(acc + bias); M = (t<0) ? Mneg : Mpos; y = clamp8((t*M + 2^(sh-1)) >>> sh)
module epilogue (
  input  logic               clk,
  input  logic               in_valid,
  input  logic signed [31:0] acc  [0:31],
  input  logic [127:0]       prm  [0:31],   // {sh, Mneg, Mpos, bias} as 4 x 32b
  output logic               out_valid,
  output logic [255:0]       y
);
  localparam logic signed [32:0] T_MAX = 33'sd67108863;   //  2^26-1
  localparam logic signed [32:0] T_MIN = -33'sd67108864;  // -2^26
  logic [4:0] v;

  for (genvar o = 0; o < 32; o++) begin : g_lane
    wire signed [31:0] bias = prm[o][31:0];
    wire        [16:0] mp   = prm[o][48:32];
    wire        [16:0] mn   = prm[o][80:64];
    wire        [5:0]  sh   = prm[o][101:96];
    wire  signed [33:0] t0 = 34'(acc[o]) + 34'(bias);
    logic signed [26:0] t1;
    logic signed [17:0] m1;
    logic [5:0]         sh1, sh2, sh3;
    logic signed [44:0] p2;
    logic signed [45:0] r3;
    logic signed [45:0] s4;
    logic [7:0]         y5;
    always_ff @(posedge clk) begin
      // E1: bias add + saturate to 27 bits, pick multiplier
      if (t0 > 34'(T_MAX))      t1 <= T_MAX[26:0];
      else if (t0 < 34'(T_MIN)) t1 <= T_MIN[26:0];
      else                      t1 <= t0[26:0];
      m1  <= (t0 < 0) ? $signed({1'b0, mn}) : $signed({1'b0, mp});
      sh1 <= sh;
      // E2: multiply (27 x 18 -> DSP)
      p2  <= t1 * m1;
      sh2 <= sh1;
      // E3: rounding constant
      r3  <= 46'(p2) + (46'sd1 <<< (sh2 - 6'd1));
      sh3 <= sh2;
      // E4: arithmetic shift
      s4  <= r3 >>> sh3;
      // E5: clamp to int8
      if (s4 > 46'sd127)       y5 <= 8'h7F;
      else if (s4 < -46'sd128) y5 <= 8'h80;
      else                     y5 <= s4[7:0];
    end
    assign y[8*o +: 8] = y5;
  end

  always_ff @(posedge clk) v <= {v[3:0], in_valid};
  assign out_valid = v[4];
endmodule
