// Loads one 32-output-channel group: 32 parameter beats, then 32*kkcc weight beats
// ordered [o][tap][c]. Weights go to bank o at address tap*cc+c (= running index).
module weight_loader (
  input  logic         clk,
  input  logic         rst_n,
  input  logic         start,
  input  logic [31:0]  addr,
  input  logic [15:0]  kkcc,
  output logic         done,        // level, until next start
  // AXI read (via mux)
  output logic         ar_valid,
  input  logic         ar_ready,
  output logic [31:0]  ar_addr,
  output logic [7:0]   ar_len,
  input  logic         r_valid,
  input  logic [127:0] r_data,
  // parameter + weight write ports
  output logic         prm_we,
  output logic [4:0]   prm_idx,
  output logic [127:0] prm_data,
  output logic         wb_we,
  output logic [4:0]   wb_bank,
  output logic [8:0]   wb_addr,
  output logic [127:0] wb_data
);
  logic        cmd_valid, cmd_ready;
  logic [23:0] total;
  logic        active, params_phase;
  logic [4:0]  o;
  logic [15:0] a;
  logic [5:0]  pcnt;

  assign total = 24'd32 + {3'd0, kkcc, 5'd0};

  burst_gen u_bg (
    .clk, .rst_n, .cmd_valid, .cmd_ready, .cmd_addr(addr), .cmd_beats(total),
    .ar_valid, .ar_ready, .ar_addr, .ar_len);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cmd_valid <= 1'b0; active <= 1'b0; done <= 1'b0;
      params_phase <= 1'b0; o <= '0; a <= '0; pcnt <= '0;
      prm_we <= 1'b0; wb_we <= 1'b0;
      prm_idx <= '0; prm_data <= '0; wb_bank <= '0; wb_addr <= '0; wb_data <= '0;
    end else begin
      prm_we <= 1'b0; wb_we <= 1'b0;
      if (cmd_valid && cmd_ready) cmd_valid <= 1'b0;
      if (start) begin
        cmd_valid <= 1'b1; active <= 1'b1; done <= 1'b0;
        params_phase <= 1'b1; o <= '0; a <= '0; pcnt <= '0;
      end else if (active && r_valid) begin
        if (params_phase) begin
          prm_we <= 1'b1; prm_idx <= pcnt[4:0]; prm_data <= r_data;
          pcnt <= pcnt + 1'b1;
          if (pcnt == 6'd31) params_phase <= 1'b0;
        end else begin
          wb_we <= 1'b1; wb_bank <= o; wb_addr <= a[8:0]; wb_data <= r_data;
          if (a == kkcc - 1'b1) begin
            a <= '0;
            o <= o + 1'b1;
            if (o == 5'd31) begin active <= 1'b0; done <= 1'b1; end
          end else begin
            a <= a + 1'b1;
          end
        end
      end
    end
  end
endmodule
