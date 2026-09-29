// YOLOv4-tiny INT8 accelerator top.
//  - AXI4-Lite slave  : control / status (axil_regs)
//  - AXI4 master 128b : descriptors, weights, feature maps (DDR via S_AXI_HP0_FPD)
// Per layer: fetch 64-byte descriptor, then for every 32-output-channel group:
//   load params+weights  ->  stream rows (line_loader) / compute (conv_engine) / write (writer)
// At layer end all write responses are awaited (next layer may read this layer's output).
module yolo_accel (
  input  logic          clk,
  input  logic          rst_n,
  // AXI-Lite slave
  input  logic [7:0]    s_axi_awaddr,
  input  logic          s_axi_awvalid,
  output logic          s_axi_awready,
  input  logic [31:0]   s_axi_wdata,
  input  logic [3:0]    s_axi_wstrb,
  input  logic          s_axi_wvalid,
  output logic          s_axi_wready,
  output logic [1:0]    s_axi_bresp,
  output logic          s_axi_bvalid,
  input  logic          s_axi_bready,
  input  logic [7:0]    s_axi_araddr,
  input  logic          s_axi_arvalid,
  output logic          s_axi_arready,
  output logic [31:0]   s_axi_rdata,
  output logic [1:0]    s_axi_rresp,
  output logic          s_axi_rvalid,
  input  logic          s_axi_rready,
  // AXI4 master
  output logic [0:0]    m_axi_awid,
  output logic [31:0]   m_axi_awaddr,
  output logic [7:0]    m_axi_awlen,
  output logic [2:0]    m_axi_awsize,
  output logic [1:0]    m_axi_awburst,
  output logic          m_axi_awlock,
  output logic [3:0]    m_axi_awcache,
  output logic [2:0]    m_axi_awprot,
  output logic [3:0]    m_axi_awqos,
  output logic          m_axi_awvalid,
  input  logic          m_axi_awready,
  output logic [127:0]  m_axi_wdata,
  output logic [15:0]   m_axi_wstrb,
  output logic          m_axi_wlast,
  output logic          m_axi_wvalid,
  input  logic          m_axi_wready,
  input  logic [0:0]    m_axi_bid,
  input  logic [1:0]    m_axi_bresp,
  input  logic          m_axi_bvalid,
  output logic          m_axi_bready,
  output logic [0:0]    m_axi_arid,
  output logic [31:0]   m_axi_araddr,
  output logic [7:0]    m_axi_arlen,
  output logic [2:0]    m_axi_arsize,
  output logic [1:0]    m_axi_arburst,
  output logic          m_axi_arlock,
  output logic [3:0]    m_axi_arcache,
  output logic [2:0]    m_axi_arprot,
  output logic [3:0]    m_axi_arqos,
  output logic          m_axi_arvalid,
  input  logic          m_axi_arready,
  input  logic [0:0]    m_axi_rid,
  input  logic [127:0]  m_axi_rdata,
  input  logic [1:0]    m_axi_rresp,
  input  logic          m_axi_rlast,
  input  logic          m_axi_rvalid,
  output logic          m_axi_rready,
  output logic          irq
);
  import yolo_pkg::*;

  // ---------------- registers ----------------
  logic        start;
  logic [31:0] desc_base;
  logic [15:0] num_layers;
  logic        busy, done_pulse;
  logic [31:0] cycles, st_row, st_out, wl_cyc;
  logic [15:0] layer;

  axil_regs u_regs (
    .clk, .rst_n,
    .s_awaddr(s_axi_awaddr), .s_awvalid(s_axi_awvalid), .s_awready(s_axi_awready),
    .s_wdata(s_axi_wdata), .s_wstrb(s_axi_wstrb), .s_wvalid(s_axi_wvalid), .s_wready(s_axi_wready),
    .s_bresp(s_axi_bresp), .s_bvalid(s_axi_bvalid), .s_bready(s_axi_bready),
    .s_araddr(s_axi_araddr), .s_arvalid(s_axi_arvalid), .s_arready(s_axi_arready),
    .s_rdata(s_axi_rdata), .s_rresp(s_axi_rresp), .s_rvalid(s_axi_rvalid), .s_rready(s_axi_rready),
    .start, .desc_addr(desc_base), .num_layers, .busy, .done_pulse, .cycles, .cur_layer(layer),
    .stall_row(st_row), .stall_out(st_out), .wload_cyc(wl_cyc), .irq);

  // ---------------- control FSM ----------------
  typedef enum logic [3:0] {
    C_IDLE, C_DESC_AR, C_DESC_R, C_DECODE, C_WL_START, C_WL_WAIT,
    C_ST_START, C_ST_WAIT, C_LAYER_END, C_DONE
  } cst_t;
  cst_t cst;
  desc_t dsc;
  logic [511:0] draw;
  logic [1:0]   dbeat;
  logic [7:0]   grp;
  logic [31:0]  waddr;
  logic         wl_start, st_start;
  logic [1:0]   rsel;          // 0: descriptor, 1: weights, 2: lines

  // sub-module status
  logic wl_done, ll_done, eng_idone, wr_idle, of_empty;
  logic [OFIFO_LG:0] credits;
  logic [15:0] outstanding;
  logic        eng_stall_row, eng_stall_out;

  // descriptor read request
  logic        d_arvalid;
  wire  [31:0] d_araddr = desc_base + {10'd0, layer, 6'd0};

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cst <= C_IDLE; busy <= 1'b0; done_pulse <= 1'b0; layer <= '0; grp <= '0;
      wl_start <= 1'b0; st_start <= 1'b0; d_arvalid <= 1'b0; dbeat <= '0; rsel <= 2'd0;
      cycles <= '0; st_row <= '0; st_out <= '0; wl_cyc <= '0; waddr <= '0; draw <= '0;
      dsc <= '0;
    end else begin
      done_pulse <= 1'b0; wl_start <= 1'b0; st_start <= 1'b0;
      if (busy) cycles <= cycles + 1'b1;
      if (eng_stall_row) st_row <= st_row + 1'b1;
      if (eng_stall_out) st_out <= st_out + 1'b1;
      if (cst == C_WL_WAIT) wl_cyc <= wl_cyc + 1'b1;
      case (cst)
        C_IDLE: if (start) begin
          busy <= 1'b1; layer <= '0; cycles <= '0; st_row <= '0; st_out <= '0; wl_cyc <= '0;
          cst <= (num_layers == 0) ? C_DONE : C_DESC_AR;
        end
        C_DESC_AR: begin
          rsel <= 2'd0; d_arvalid <= 1'b1; dbeat <= '0;
          if (d_arvalid && m_axi_arready) begin d_arvalid <= 1'b0; cst <= C_DESC_R; end
        end
        C_DESC_R: if (m_axi_rvalid) begin
          draw[dbeat*128 +: 128] <= m_axi_rdata;
          dbeat <= dbeat + 1'b1;
          if (dbeat == 2'd3) cst <= C_DECODE;
        end
        C_DECODE: begin
          dsc <= unpack_desc(draw); grp <= '0; cst <= C_WL_START;
        end
        C_WL_START: begin
          if (grp == 0) waddr <= dsc.w_addr;
          rsel <= 2'd1; wl_start <= 1'b1; cst <= C_WL_WAIT;
        end
        C_WL_WAIT: if (wl_done && !wl_start) begin
          rsel <= 2'd2; st_start <= 1'b1; cst <= C_ST_START;
        end
        C_ST_START: cst <= C_ST_WAIT;
        C_ST_WAIT: if (eng_idone && ll_done && wr_idle && of_empty && credits == 0) begin
          waddr <= waddr + dsc.grp_bytes;
          if (grp == dsc.ngrp - 1'b1) cst <= C_LAYER_END;
          else begin grp <= grp + 1'b1; cst <= C_WL_START; end
        end
        C_LAYER_END: if (outstanding == 0) begin
          if (layer == num_layers - 1'b1) cst <= C_DONE;
          else begin layer <= layer + 1'b1; cst <= C_DESC_AR; end
        end
        C_DONE: begin busy <= 1'b0; done_pulse <= 1'b1; cst <= C_IDLE; end
        default: cst <= C_IDLE;
      endcase
    end
  end
  // weight address of the group being started: dsc.w_addr for group 0, else the running address
  wire [31:0] wl_addr = (grp == 0) ? dsc.w_addr : waddr;

  // ---------------- AXI read mux ----------------
  logic        wl_arvalid, ll_arvalid;
  logic [31:0] wl_araddr, ll_araddr;
  logic [7:0]  wl_arlen, ll_arlen;
  always_comb begin
    case (rsel)
      2'd0:    begin m_axi_arvalid = d_arvalid;  m_axi_araddr = d_araddr;  m_axi_arlen = 8'd3;     end
      2'd1:    begin m_axi_arvalid = wl_arvalid; m_axi_araddr = wl_araddr; m_axi_arlen = wl_arlen; end
      default: begin m_axi_arvalid = ll_arvalid; m_axi_araddr = ll_araddr; m_axi_arlen = ll_arlen; end
    endcase
  end
  assign m_axi_arid    = '0;
  assign m_axi_arsize  = 3'd4;       // 16 bytes
  assign m_axi_arburst = 2'b01;      // INCR
  assign m_axi_arlock  = 1'b0;
  assign m_axi_arcache = 4'b0011;
  assign m_axi_arprot  = 3'b000;
  assign m_axi_arqos   = 4'd0;
  assign m_axi_rready  = 1'b1;       // every client sinks one beat per cycle
  wire wl_rvalid = m_axi_rvalid && (rsel == 2'd1);
  wire ll_rvalid = m_axi_rvalid && (rsel == 2'd2);

  // ---------------- sub-modules ----------------
  logic         prm_we, wb_we, lb_we;
  logic [4:0]   prm_idx, wb_bank;
  logic [8:0]   wb_addr;
  logic [12:0]  lb_waddr;
  logic [127:0] prm_data, wb_data, lb_wdata;
  logic signed [17:0] row_limit;
  logic [15:0]  rows_done;
  logic [255:0] of_dout;
  logic         of_pop;

  weight_loader u_wl (
    .clk, .rst_n, .start(wl_start), .addr(wl_addr), .kkcc(dsc.kkcc), .done(wl_done),
    .ar_valid(wl_arvalid), .ar_ready(m_axi_arready && rsel == 2'd1), .ar_addr(wl_araddr), .ar_len(wl_arlen),
    .r_valid(wl_rvalid), .r_data(m_axi_rdata),
    .prm_we, .prm_idx, .prm_data, .wb_we, .wb_bank, .wb_addr, .wb_data);

  line_loader u_ll (
    .clk, .rst_n, .start(st_start), .in_addr(dsc.in_addr), .in_w(dsc.in_w), .in_ps(dsc.in_ps),
    .cc(dsc.cc), .pool(dsc.pool), .in_hc(dsc.in_hc), .row_limit, .rows_done, .done(ll_done),
    .ar_valid(ll_arvalid), .ar_ready(m_axi_arready && rsel == 2'd2), .ar_addr(ll_araddr), .ar_len(ll_arlen),
    .r_valid(ll_rvalid), .r_data(m_axi_rdata),
    .lb_we, .lb_waddr, .lb_wdata);

  conv_engine u_eng (
    .clk, .rst_n, .start(st_start),
    .in_wc(dsc.in_wc), .in_hc(dsc.in_hc), .out_w(dsc.out_w), .out_h(dsc.out_h),
    .cc(dsc.cc), .k(dsc.k), .s(dsc.s), .pad(dsc.pad), .kkcc(dsc.kkcc),
    .issue_done(eng_idone), .row_limit, .rows_done,
    .prm_we, .prm_idx, .prm_data, .wb_we, .wb_bank, .wb_addr, .wb_data,
    .lb_we, .lb_waddr, .lb_wdata,
    .of_dout, .of_empty, .of_pop, .credits,
    .stall_row(eng_stall_row), .stall_out(eng_stall_out));

  writer u_wr (
    .clk, .rst_n, .start(st_start),
    .addr0(dsc.out_addr), .addr1(dsc.out2_addr), .ps0(dsc.out_ps), .ps1(dsc.out2_ps),
    .en1(dsc.out2_en), .ups(dsc.ups), .out_w(dsc.out_w), .grp(grp), .idle(wr_idle),
    .of_dout, .of_empty, .of_pop,
    .aw_valid(m_axi_awvalid), .aw_ready(m_axi_awready), .aw_addr(m_axi_awaddr), .aw_len(m_axi_awlen),
    .w_valid(m_axi_wvalid), .w_ready(m_axi_wready), .w_data(m_axi_wdata), .w_last(m_axi_wlast),
    .b_valid(m_axi_bvalid), .outstanding);

  assign m_axi_awid    = '0;
  assign m_axi_awsize  = 3'd4;
  assign m_axi_awburst = 2'b01;
  assign m_axi_awlock  = 1'b0;
  assign m_axi_awcache = 4'b0011;
  assign m_axi_awprot  = 3'b000;
  assign m_axi_awqos   = 4'd0;
  assign m_axi_wstrb   = 16'hFFFF;
  assign m_axi_bready  = 1'b1;
endmodule
