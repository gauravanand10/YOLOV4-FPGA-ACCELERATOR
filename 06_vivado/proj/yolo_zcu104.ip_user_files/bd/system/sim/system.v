//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2024.1 (win64) Build 5076996 Wed May 22 18:37:14 MDT 2024
//Date        : Mon Sep 28 01:34:22 2026
//Host        : Gaurav running 64-bit major release  (build 9200)
//Command     : generate_target system.bd
//Design      : system
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CORE_GENERATION_INFO = "system,IP_Integrator,{x_ipVendor=xilinx.com,x_ipLibrary=BlockDiagram,x_ipName=system,x_ipVersion=1.00.a,x_ipLanguage=VERILOG,numBlks=5,numReposBlks=5,numNonXlnxBlks=0,numHierBlks=0,maxHierDepth=0,numSysgenBlks=0,numHlsBlks=0,numHdlrefBlks=1,numPkgbdBlks=0,bdsource=USER,da_zynq_ultra_ps_e_cnt=1,synth_mode=None}" *) (* HW_HANDOFF = "system.hwdef" *) 
module system
   ();

  wire [0:0]rst_pl0_interconnect_aresetn;
  wire [0:0]rst_pl0_peripheral_aresetn;
  wire [7:0]sc_ctrl_M00_AXI_ARADDR;
  wire sc_ctrl_M00_AXI_ARREADY;
  wire sc_ctrl_M00_AXI_ARVALID;
  wire [7:0]sc_ctrl_M00_AXI_AWADDR;
  wire sc_ctrl_M00_AXI_AWREADY;
  wire sc_ctrl_M00_AXI_AWVALID;
  wire sc_ctrl_M00_AXI_BREADY;
  wire [1:0]sc_ctrl_M00_AXI_BRESP;
  wire sc_ctrl_M00_AXI_BVALID;
  wire [31:0]sc_ctrl_M00_AXI_RDATA;
  wire sc_ctrl_M00_AXI_RREADY;
  wire [1:0]sc_ctrl_M00_AXI_RRESP;
  wire sc_ctrl_M00_AXI_RVALID;
  wire [31:0]sc_ctrl_M00_AXI_WDATA;
  wire sc_ctrl_M00_AXI_WREADY;
  wire [3:0]sc_ctrl_M00_AXI_WSTRB;
  wire sc_ctrl_M00_AXI_WVALID;
  wire [48:0]sc_mem_M00_AXI_ARADDR;
  wire [1:0]sc_mem_M00_AXI_ARBURST;
  wire [3:0]sc_mem_M00_AXI_ARCACHE;
  wire [7:0]sc_mem_M00_AXI_ARLEN;
  wire [0:0]sc_mem_M00_AXI_ARLOCK;
  wire [2:0]sc_mem_M00_AXI_ARPROT;
  wire [3:0]sc_mem_M00_AXI_ARQOS;
  wire sc_mem_M00_AXI_ARREADY;
  wire [2:0]sc_mem_M00_AXI_ARSIZE;
  wire [0:0]sc_mem_M00_AXI_ARUSER;
  wire sc_mem_M00_AXI_ARVALID;
  wire [48:0]sc_mem_M00_AXI_AWADDR;
  wire [1:0]sc_mem_M00_AXI_AWBURST;
  wire [3:0]sc_mem_M00_AXI_AWCACHE;
  wire [7:0]sc_mem_M00_AXI_AWLEN;
  wire [0:0]sc_mem_M00_AXI_AWLOCK;
  wire [2:0]sc_mem_M00_AXI_AWPROT;
  wire [3:0]sc_mem_M00_AXI_AWQOS;
  wire sc_mem_M00_AXI_AWREADY;
  wire [2:0]sc_mem_M00_AXI_AWSIZE;
  wire [0:0]sc_mem_M00_AXI_AWUSER;
  wire sc_mem_M00_AXI_AWVALID;
  wire sc_mem_M00_AXI_BREADY;
  wire [1:0]sc_mem_M00_AXI_BRESP;
  wire sc_mem_M00_AXI_BVALID;
  wire [127:0]sc_mem_M00_AXI_RDATA;
  wire sc_mem_M00_AXI_RLAST;
  wire sc_mem_M00_AXI_RREADY;
  wire [1:0]sc_mem_M00_AXI_RRESP;
  wire sc_mem_M00_AXI_RVALID;
  wire [127:0]sc_mem_M00_AXI_WDATA;
  wire sc_mem_M00_AXI_WLAST;
  wire sc_mem_M00_AXI_WREADY;
  wire [15:0]sc_mem_M00_AXI_WSTRB;
  wire sc_mem_M00_AXI_WVALID;
  wire yolo_accel_irq;
  wire [31:0]yolo_accel_m_axi_ARADDR;
  wire [1:0]yolo_accel_m_axi_ARBURST;
  wire [3:0]yolo_accel_m_axi_ARCACHE;
  wire [0:0]yolo_accel_m_axi_ARID;
  wire [7:0]yolo_accel_m_axi_ARLEN;
  wire yolo_accel_m_axi_ARLOCK;
  wire [2:0]yolo_accel_m_axi_ARPROT;
  wire [3:0]yolo_accel_m_axi_ARQOS;
  wire yolo_accel_m_axi_ARREADY;
  wire [2:0]yolo_accel_m_axi_ARSIZE;
  wire [0:0]yolo_accel_m_axi_ARUSER;
  wire yolo_accel_m_axi_ARVALID;
  wire [31:0]yolo_accel_m_axi_AWADDR;
  wire [1:0]yolo_accel_m_axi_AWBURST;
  wire [3:0]yolo_accel_m_axi_AWCACHE;
  wire [0:0]yolo_accel_m_axi_AWID;
  wire [7:0]yolo_accel_m_axi_AWLEN;
  wire yolo_accel_m_axi_AWLOCK;
  wire [2:0]yolo_accel_m_axi_AWPROT;
  wire [3:0]yolo_accel_m_axi_AWQOS;
  wire yolo_accel_m_axi_AWREADY;
  wire [2:0]yolo_accel_m_axi_AWSIZE;
  wire [0:0]yolo_accel_m_axi_AWUSER;
  wire yolo_accel_m_axi_AWVALID;
  wire [0:0]yolo_accel_m_axi_BID;
  wire yolo_accel_m_axi_BREADY;
  wire [1:0]yolo_accel_m_axi_BRESP;
  wire yolo_accel_m_axi_BVALID;
  wire [127:0]yolo_accel_m_axi_RDATA;
  wire [0:0]yolo_accel_m_axi_RID;
  wire yolo_accel_m_axi_RLAST;
  wire yolo_accel_m_axi_RREADY;
  wire [1:0]yolo_accel_m_axi_RRESP;
  wire yolo_accel_m_axi_RVALID;
  wire [127:0]yolo_accel_m_axi_WDATA;
  wire yolo_accel_m_axi_WLAST;
  wire yolo_accel_m_axi_WREADY;
  wire [15:0]yolo_accel_m_axi_WSTRB;
  wire yolo_accel_m_axi_WVALID;
  wire [39:0]zynq_ps_M_AXI_HPM0_FPD_ARADDR;
  wire [1:0]zynq_ps_M_AXI_HPM0_FPD_ARBURST;
  wire [3:0]zynq_ps_M_AXI_HPM0_FPD_ARCACHE;
  wire [15:0]zynq_ps_M_AXI_HPM0_FPD_ARID;
  wire [7:0]zynq_ps_M_AXI_HPM0_FPD_ARLEN;
  wire zynq_ps_M_AXI_HPM0_FPD_ARLOCK;
  wire [2:0]zynq_ps_M_AXI_HPM0_FPD_ARPROT;
  wire [3:0]zynq_ps_M_AXI_HPM0_FPD_ARQOS;
  wire zynq_ps_M_AXI_HPM0_FPD_ARREADY;
  wire [2:0]zynq_ps_M_AXI_HPM0_FPD_ARSIZE;
  wire [15:0]zynq_ps_M_AXI_HPM0_FPD_ARUSER;
  wire zynq_ps_M_AXI_HPM0_FPD_ARVALID;
  wire [39:0]zynq_ps_M_AXI_HPM0_FPD_AWADDR;
  wire [1:0]zynq_ps_M_AXI_HPM0_FPD_AWBURST;
  wire [3:0]zynq_ps_M_AXI_HPM0_FPD_AWCACHE;
  wire [15:0]zynq_ps_M_AXI_HPM0_FPD_AWID;
  wire [7:0]zynq_ps_M_AXI_HPM0_FPD_AWLEN;
  wire zynq_ps_M_AXI_HPM0_FPD_AWLOCK;
  wire [2:0]zynq_ps_M_AXI_HPM0_FPD_AWPROT;
  wire [3:0]zynq_ps_M_AXI_HPM0_FPD_AWQOS;
  wire zynq_ps_M_AXI_HPM0_FPD_AWREADY;
  wire [2:0]zynq_ps_M_AXI_HPM0_FPD_AWSIZE;
  wire [15:0]zynq_ps_M_AXI_HPM0_FPD_AWUSER;
  wire zynq_ps_M_AXI_HPM0_FPD_AWVALID;
  wire [15:0]zynq_ps_M_AXI_HPM0_FPD_BID;
  wire zynq_ps_M_AXI_HPM0_FPD_BREADY;
  wire [1:0]zynq_ps_M_AXI_HPM0_FPD_BRESP;
  wire zynq_ps_M_AXI_HPM0_FPD_BVALID;
  wire [31:0]zynq_ps_M_AXI_HPM0_FPD_RDATA;
  wire [15:0]zynq_ps_M_AXI_HPM0_FPD_RID;
  wire zynq_ps_M_AXI_HPM0_FPD_RLAST;
  wire zynq_ps_M_AXI_HPM0_FPD_RREADY;
  wire [1:0]zynq_ps_M_AXI_HPM0_FPD_RRESP;
  wire zynq_ps_M_AXI_HPM0_FPD_RVALID;
  wire [31:0]zynq_ps_M_AXI_HPM0_FPD_WDATA;
  wire zynq_ps_M_AXI_HPM0_FPD_WLAST;
  wire zynq_ps_M_AXI_HPM0_FPD_WREADY;
  wire [3:0]zynq_ps_M_AXI_HPM0_FPD_WSTRB;
  wire zynq_ps_M_AXI_HPM0_FPD_WVALID;
  wire zynq_ps_pl_clk0;
  wire zynq_ps_pl_resetn0;

  system_rst_pl0_0 rst_pl0
       (.aux_reset_in(1'b1),
        .dcm_locked(1'b1),
        .ext_reset_in(zynq_ps_pl_resetn0),
        .interconnect_aresetn(rst_pl0_interconnect_aresetn),
        .mb_debug_sys_rst(1'b0),
        .peripheral_aresetn(rst_pl0_peripheral_aresetn),
        .slowest_sync_clk(zynq_ps_pl_clk0));
  system_sc_ctrl_0 sc_ctrl
       (.M00_AXI_araddr(sc_ctrl_M00_AXI_ARADDR),
        .M00_AXI_arready(sc_ctrl_M00_AXI_ARREADY),
        .M00_AXI_arvalid(sc_ctrl_M00_AXI_ARVALID),
        .M00_AXI_awaddr(sc_ctrl_M00_AXI_AWADDR),
        .M00_AXI_awready(sc_ctrl_M00_AXI_AWREADY),
        .M00_AXI_awvalid(sc_ctrl_M00_AXI_AWVALID),
        .M00_AXI_bready(sc_ctrl_M00_AXI_BREADY),
        .M00_AXI_bresp(sc_ctrl_M00_AXI_BRESP),
        .M00_AXI_bvalid(sc_ctrl_M00_AXI_BVALID),
        .M00_AXI_rdata(sc_ctrl_M00_AXI_RDATA),
        .M00_AXI_rready(sc_ctrl_M00_AXI_RREADY),
        .M00_AXI_rresp(sc_ctrl_M00_AXI_RRESP),
        .M00_AXI_rvalid(sc_ctrl_M00_AXI_RVALID),
        .M00_AXI_wdata(sc_ctrl_M00_AXI_WDATA),
        .M00_AXI_wready(sc_ctrl_M00_AXI_WREADY),
        .M00_AXI_wstrb(sc_ctrl_M00_AXI_WSTRB),
        .M00_AXI_wvalid(sc_ctrl_M00_AXI_WVALID),
        .S00_AXI_araddr(zynq_ps_M_AXI_HPM0_FPD_ARADDR),
        .S00_AXI_arburst(zynq_ps_M_AXI_HPM0_FPD_ARBURST),
        .S00_AXI_arcache(zynq_ps_M_AXI_HPM0_FPD_ARCACHE),
        .S00_AXI_arid(zynq_ps_M_AXI_HPM0_FPD_ARID),
        .S00_AXI_arlen(zynq_ps_M_AXI_HPM0_FPD_ARLEN),
        .S00_AXI_arlock(zynq_ps_M_AXI_HPM0_FPD_ARLOCK),
        .S00_AXI_arprot(zynq_ps_M_AXI_HPM0_FPD_ARPROT),
        .S00_AXI_arqos(zynq_ps_M_AXI_HPM0_FPD_ARQOS),
        .S00_AXI_arready(zynq_ps_M_AXI_HPM0_FPD_ARREADY),
        .S00_AXI_arsize(zynq_ps_M_AXI_HPM0_FPD_ARSIZE),
        .S00_AXI_aruser(zynq_ps_M_AXI_HPM0_FPD_ARUSER),
        .S00_AXI_arvalid(zynq_ps_M_AXI_HPM0_FPD_ARVALID),
        .S00_AXI_awaddr(zynq_ps_M_AXI_HPM0_FPD_AWADDR),
        .S00_AXI_awburst(zynq_ps_M_AXI_HPM0_FPD_AWBURST),
        .S00_AXI_awcache(zynq_ps_M_AXI_HPM0_FPD_AWCACHE),
        .S00_AXI_awid(zynq_ps_M_AXI_HPM0_FPD_AWID),
        .S00_AXI_awlen(zynq_ps_M_AXI_HPM0_FPD_AWLEN),
        .S00_AXI_awlock(zynq_ps_M_AXI_HPM0_FPD_AWLOCK),
        .S00_AXI_awprot(zynq_ps_M_AXI_HPM0_FPD_AWPROT),
        .S00_AXI_awqos(zynq_ps_M_AXI_HPM0_FPD_AWQOS),
        .S00_AXI_awready(zynq_ps_M_AXI_HPM0_FPD_AWREADY),
        .S00_AXI_awsize(zynq_ps_M_AXI_HPM0_FPD_AWSIZE),
        .S00_AXI_awuser(zynq_ps_M_AXI_HPM0_FPD_AWUSER),
        .S00_AXI_awvalid(zynq_ps_M_AXI_HPM0_FPD_AWVALID),
        .S00_AXI_bid(zynq_ps_M_AXI_HPM0_FPD_BID),
        .S00_AXI_bready(zynq_ps_M_AXI_HPM0_FPD_BREADY),
        .S00_AXI_bresp(zynq_ps_M_AXI_HPM0_FPD_BRESP),
        .S00_AXI_bvalid(zynq_ps_M_AXI_HPM0_FPD_BVALID),
        .S00_AXI_rdata(zynq_ps_M_AXI_HPM0_FPD_RDATA),
        .S00_AXI_rid(zynq_ps_M_AXI_HPM0_FPD_RID),
        .S00_AXI_rlast(zynq_ps_M_AXI_HPM0_FPD_RLAST),
        .S00_AXI_rready(zynq_ps_M_AXI_HPM0_FPD_RREADY),
        .S00_AXI_rresp(zynq_ps_M_AXI_HPM0_FPD_RRESP),
        .S00_AXI_rvalid(zynq_ps_M_AXI_HPM0_FPD_RVALID),
        .S00_AXI_wdata(zynq_ps_M_AXI_HPM0_FPD_WDATA),
        .S00_AXI_wlast(zynq_ps_M_AXI_HPM0_FPD_WLAST),
        .S00_AXI_wready(zynq_ps_M_AXI_HPM0_FPD_WREADY),
        .S00_AXI_wstrb(zynq_ps_M_AXI_HPM0_FPD_WSTRB),
        .S00_AXI_wvalid(zynq_ps_M_AXI_HPM0_FPD_WVALID),
        .aclk(zynq_ps_pl_clk0),
        .aresetn(rst_pl0_interconnect_aresetn));
  system_sc_mem_0 sc_mem
       (.M00_AXI_araddr(sc_mem_M00_AXI_ARADDR),
        .M00_AXI_arburst(sc_mem_M00_AXI_ARBURST),
        .M00_AXI_arcache(sc_mem_M00_AXI_ARCACHE),
        .M00_AXI_arlen(sc_mem_M00_AXI_ARLEN),
        .M00_AXI_arlock(sc_mem_M00_AXI_ARLOCK),
        .M00_AXI_arprot(sc_mem_M00_AXI_ARPROT),
        .M00_AXI_arqos(sc_mem_M00_AXI_ARQOS),
        .M00_AXI_arready(sc_mem_M00_AXI_ARREADY),
        .M00_AXI_arsize(sc_mem_M00_AXI_ARSIZE),
        .M00_AXI_aruser(sc_mem_M00_AXI_ARUSER),
        .M00_AXI_arvalid(sc_mem_M00_AXI_ARVALID),
        .M00_AXI_awaddr(sc_mem_M00_AXI_AWADDR),
        .M00_AXI_awburst(sc_mem_M00_AXI_AWBURST),
        .M00_AXI_awcache(sc_mem_M00_AXI_AWCACHE),
        .M00_AXI_awlen(sc_mem_M00_AXI_AWLEN),
        .M00_AXI_awlock(sc_mem_M00_AXI_AWLOCK),
        .M00_AXI_awprot(sc_mem_M00_AXI_AWPROT),
        .M00_AXI_awqos(sc_mem_M00_AXI_AWQOS),
        .M00_AXI_awready(sc_mem_M00_AXI_AWREADY),
        .M00_AXI_awsize(sc_mem_M00_AXI_AWSIZE),
        .M00_AXI_awuser(sc_mem_M00_AXI_AWUSER),
        .M00_AXI_awvalid(sc_mem_M00_AXI_AWVALID),
        .M00_AXI_bready(sc_mem_M00_AXI_BREADY),
        .M00_AXI_bresp(sc_mem_M00_AXI_BRESP),
        .M00_AXI_bvalid(sc_mem_M00_AXI_BVALID),
        .M00_AXI_rdata(sc_mem_M00_AXI_RDATA),
        .M00_AXI_rlast(sc_mem_M00_AXI_RLAST),
        .M00_AXI_rready(sc_mem_M00_AXI_RREADY),
        .M00_AXI_rresp(sc_mem_M00_AXI_RRESP),
        .M00_AXI_rvalid(sc_mem_M00_AXI_RVALID),
        .M00_AXI_wdata(sc_mem_M00_AXI_WDATA),
        .M00_AXI_wlast(sc_mem_M00_AXI_WLAST),
        .M00_AXI_wready(sc_mem_M00_AXI_WREADY),
        .M00_AXI_wstrb(sc_mem_M00_AXI_WSTRB),
        .M00_AXI_wvalid(sc_mem_M00_AXI_WVALID),
        .S00_AXI_araddr(yolo_accel_m_axi_ARADDR),
        .S00_AXI_arburst(yolo_accel_m_axi_ARBURST),
        .S00_AXI_arcache(yolo_accel_m_axi_ARCACHE),
        .S00_AXI_arid(yolo_accel_m_axi_ARID),
        .S00_AXI_arlen(yolo_accel_m_axi_ARLEN),
        .S00_AXI_arlock(yolo_accel_m_axi_ARLOCK),
        .S00_AXI_arprot(yolo_accel_m_axi_ARPROT),
        .S00_AXI_arqos(yolo_accel_m_axi_ARQOS),
        .S00_AXI_arready(yolo_accel_m_axi_ARREADY),
        .S00_AXI_arsize(yolo_accel_m_axi_ARSIZE),
        .S00_AXI_aruser(yolo_accel_m_axi_ARUSER),
        .S00_AXI_arvalid(yolo_accel_m_axi_ARVALID),
        .S00_AXI_awaddr(yolo_accel_m_axi_AWADDR),
        .S00_AXI_awburst(yolo_accel_m_axi_AWBURST),
        .S00_AXI_awcache(yolo_accel_m_axi_AWCACHE),
        .S00_AXI_awid(yolo_accel_m_axi_AWID),
        .S00_AXI_awlen(yolo_accel_m_axi_AWLEN),
        .S00_AXI_awlock(yolo_accel_m_axi_AWLOCK),
        .S00_AXI_awprot(yolo_accel_m_axi_AWPROT),
        .S00_AXI_awqos(yolo_accel_m_axi_AWQOS),
        .S00_AXI_awready(yolo_accel_m_axi_AWREADY),
        .S00_AXI_awsize(yolo_accel_m_axi_AWSIZE),
        .S00_AXI_awuser(yolo_accel_m_axi_AWUSER),
        .S00_AXI_awvalid(yolo_accel_m_axi_AWVALID),
        .S00_AXI_bid(yolo_accel_m_axi_BID),
        .S00_AXI_bready(yolo_accel_m_axi_BREADY),
        .S00_AXI_bresp(yolo_accel_m_axi_BRESP),
        .S00_AXI_bvalid(yolo_accel_m_axi_BVALID),
        .S00_AXI_rdata(yolo_accel_m_axi_RDATA),
        .S00_AXI_rid(yolo_accel_m_axi_RID),
        .S00_AXI_rlast(yolo_accel_m_axi_RLAST),
        .S00_AXI_rready(yolo_accel_m_axi_RREADY),
        .S00_AXI_rresp(yolo_accel_m_axi_RRESP),
        .S00_AXI_rvalid(yolo_accel_m_axi_RVALID),
        .S00_AXI_wdata(yolo_accel_m_axi_WDATA),
        .S00_AXI_wlast(yolo_accel_m_axi_WLAST),
        .S00_AXI_wready(yolo_accel_m_axi_WREADY),
        .S00_AXI_wstrb(yolo_accel_m_axi_WSTRB),
        .S00_AXI_wvalid(yolo_accel_m_axi_WVALID),
        .aclk(zynq_ps_pl_clk0),
        .aresetn(rst_pl0_interconnect_aresetn));
  system_yolo_accel_0 yolo_accel
       (.aclk(zynq_ps_pl_clk0),
        .aresetn(rst_pl0_peripheral_aresetn),
        .irq(yolo_accel_irq),
        .m_axi_araddr(yolo_accel_m_axi_ARADDR),
        .m_axi_arburst(yolo_accel_m_axi_ARBURST),
        .m_axi_arcache(yolo_accel_m_axi_ARCACHE),
        .m_axi_arid(yolo_accel_m_axi_ARID),
        .m_axi_arlen(yolo_accel_m_axi_ARLEN),
        .m_axi_arlock(yolo_accel_m_axi_ARLOCK),
        .m_axi_arprot(yolo_accel_m_axi_ARPROT),
        .m_axi_arqos(yolo_accel_m_axi_ARQOS),
        .m_axi_arready(yolo_accel_m_axi_ARREADY),
        .m_axi_arsize(yolo_accel_m_axi_ARSIZE),
        .m_axi_aruser(yolo_accel_m_axi_ARUSER),
        .m_axi_arvalid(yolo_accel_m_axi_ARVALID),
        .m_axi_awaddr(yolo_accel_m_axi_AWADDR),
        .m_axi_awburst(yolo_accel_m_axi_AWBURST),
        .m_axi_awcache(yolo_accel_m_axi_AWCACHE),
        .m_axi_awid(yolo_accel_m_axi_AWID),
        .m_axi_awlen(yolo_accel_m_axi_AWLEN),
        .m_axi_awlock(yolo_accel_m_axi_AWLOCK),
        .m_axi_awprot(yolo_accel_m_axi_AWPROT),
        .m_axi_awqos(yolo_accel_m_axi_AWQOS),
        .m_axi_awready(yolo_accel_m_axi_AWREADY),
        .m_axi_awsize(yolo_accel_m_axi_AWSIZE),
        .m_axi_awuser(yolo_accel_m_axi_AWUSER),
        .m_axi_awvalid(yolo_accel_m_axi_AWVALID),
        .m_axi_bid(yolo_accel_m_axi_BID),
        .m_axi_bready(yolo_accel_m_axi_BREADY),
        .m_axi_bresp(yolo_accel_m_axi_BRESP),
        .m_axi_bvalid(yolo_accel_m_axi_BVALID),
        .m_axi_rdata(yolo_accel_m_axi_RDATA),
        .m_axi_rid(yolo_accel_m_axi_RID),
        .m_axi_rlast(yolo_accel_m_axi_RLAST),
        .m_axi_rready(yolo_accel_m_axi_RREADY),
        .m_axi_rresp(yolo_accel_m_axi_RRESP),
        .m_axi_rvalid(yolo_accel_m_axi_RVALID),
        .m_axi_wdata(yolo_accel_m_axi_WDATA),
        .m_axi_wlast(yolo_accel_m_axi_WLAST),
        .m_axi_wready(yolo_accel_m_axi_WREADY),
        .m_axi_wstrb(yolo_accel_m_axi_WSTRB),
        .m_axi_wvalid(yolo_accel_m_axi_WVALID),
        .s_axi_araddr(sc_ctrl_M00_AXI_ARADDR),
        .s_axi_arready(sc_ctrl_M00_AXI_ARREADY),
        .s_axi_arvalid(sc_ctrl_M00_AXI_ARVALID),
        .s_axi_awaddr(sc_ctrl_M00_AXI_AWADDR),
        .s_axi_awready(sc_ctrl_M00_AXI_AWREADY),
        .s_axi_awvalid(sc_ctrl_M00_AXI_AWVALID),
        .s_axi_bready(sc_ctrl_M00_AXI_BREADY),
        .s_axi_bresp(sc_ctrl_M00_AXI_BRESP),
        .s_axi_bvalid(sc_ctrl_M00_AXI_BVALID),
        .s_axi_rdata(sc_ctrl_M00_AXI_RDATA),
        .s_axi_rready(sc_ctrl_M00_AXI_RREADY),
        .s_axi_rresp(sc_ctrl_M00_AXI_RRESP),
        .s_axi_rvalid(sc_ctrl_M00_AXI_RVALID),
        .s_axi_wdata(sc_ctrl_M00_AXI_WDATA),
        .s_axi_wready(sc_ctrl_M00_AXI_WREADY),
        .s_axi_wstrb(sc_ctrl_M00_AXI_WSTRB),
        .s_axi_wvalid(sc_ctrl_M00_AXI_WVALID));
  system_zynq_ps_0 zynq_ps
       (.maxigp0_araddr(zynq_ps_M_AXI_HPM0_FPD_ARADDR),
        .maxigp0_arburst(zynq_ps_M_AXI_HPM0_FPD_ARBURST),
        .maxigp0_arcache(zynq_ps_M_AXI_HPM0_FPD_ARCACHE),
        .maxigp0_arid(zynq_ps_M_AXI_HPM0_FPD_ARID),
        .maxigp0_arlen(zynq_ps_M_AXI_HPM0_FPD_ARLEN),
        .maxigp0_arlock(zynq_ps_M_AXI_HPM0_FPD_ARLOCK),
        .maxigp0_arprot(zynq_ps_M_AXI_HPM0_FPD_ARPROT),
        .maxigp0_arqos(zynq_ps_M_AXI_HPM0_FPD_ARQOS),
        .maxigp0_arready(zynq_ps_M_AXI_HPM0_FPD_ARREADY),
        .maxigp0_arsize(zynq_ps_M_AXI_HPM0_FPD_ARSIZE),
        .maxigp0_aruser(zynq_ps_M_AXI_HPM0_FPD_ARUSER),
        .maxigp0_arvalid(zynq_ps_M_AXI_HPM0_FPD_ARVALID),
        .maxigp0_awaddr(zynq_ps_M_AXI_HPM0_FPD_AWADDR),
        .maxigp0_awburst(zynq_ps_M_AXI_HPM0_FPD_AWBURST),
        .maxigp0_awcache(zynq_ps_M_AXI_HPM0_FPD_AWCACHE),
        .maxigp0_awid(zynq_ps_M_AXI_HPM0_FPD_AWID),
        .maxigp0_awlen(zynq_ps_M_AXI_HPM0_FPD_AWLEN),
        .maxigp0_awlock(zynq_ps_M_AXI_HPM0_FPD_AWLOCK),
        .maxigp0_awprot(zynq_ps_M_AXI_HPM0_FPD_AWPROT),
        .maxigp0_awqos(zynq_ps_M_AXI_HPM0_FPD_AWQOS),
        .maxigp0_awready(zynq_ps_M_AXI_HPM0_FPD_AWREADY),
        .maxigp0_awsize(zynq_ps_M_AXI_HPM0_FPD_AWSIZE),
        .maxigp0_awuser(zynq_ps_M_AXI_HPM0_FPD_AWUSER),
        .maxigp0_awvalid(zynq_ps_M_AXI_HPM0_FPD_AWVALID),
        .maxigp0_bid(zynq_ps_M_AXI_HPM0_FPD_BID),
        .maxigp0_bready(zynq_ps_M_AXI_HPM0_FPD_BREADY),
        .maxigp0_bresp(zynq_ps_M_AXI_HPM0_FPD_BRESP),
        .maxigp0_bvalid(zynq_ps_M_AXI_HPM0_FPD_BVALID),
        .maxigp0_rdata(zynq_ps_M_AXI_HPM0_FPD_RDATA),
        .maxigp0_rid(zynq_ps_M_AXI_HPM0_FPD_RID),
        .maxigp0_rlast(zynq_ps_M_AXI_HPM0_FPD_RLAST),
        .maxigp0_rready(zynq_ps_M_AXI_HPM0_FPD_RREADY),
        .maxigp0_rresp(zynq_ps_M_AXI_HPM0_FPD_RRESP),
        .maxigp0_rvalid(zynq_ps_M_AXI_HPM0_FPD_RVALID),
        .maxigp0_wdata(zynq_ps_M_AXI_HPM0_FPD_WDATA),
        .maxigp0_wlast(zynq_ps_M_AXI_HPM0_FPD_WLAST),
        .maxigp0_wready(zynq_ps_M_AXI_HPM0_FPD_WREADY),
        .maxigp0_wstrb(zynq_ps_M_AXI_HPM0_FPD_WSTRB),
        .maxigp0_wvalid(zynq_ps_M_AXI_HPM0_FPD_WVALID),
        .maxihpm0_fpd_aclk(zynq_ps_pl_clk0),
        .pl_clk0(zynq_ps_pl_clk0),
        .pl_ps_irq0(yolo_accel_irq),
        .pl_resetn0(zynq_ps_pl_resetn0),
        .saxigp2_araddr(sc_mem_M00_AXI_ARADDR),
        .saxigp2_arburst(sc_mem_M00_AXI_ARBURST),
        .saxigp2_arcache(sc_mem_M00_AXI_ARCACHE),
        .saxigp2_arid({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .saxigp2_arlen(sc_mem_M00_AXI_ARLEN),
        .saxigp2_arlock(sc_mem_M00_AXI_ARLOCK),
        .saxigp2_arprot(sc_mem_M00_AXI_ARPROT),
        .saxigp2_arqos(sc_mem_M00_AXI_ARQOS),
        .saxigp2_arready(sc_mem_M00_AXI_ARREADY),
        .saxigp2_arsize(sc_mem_M00_AXI_ARSIZE),
        .saxigp2_aruser(sc_mem_M00_AXI_ARUSER),
        .saxigp2_arvalid(sc_mem_M00_AXI_ARVALID),
        .saxigp2_awaddr(sc_mem_M00_AXI_AWADDR),
        .saxigp2_awburst(sc_mem_M00_AXI_AWBURST),
        .saxigp2_awcache(sc_mem_M00_AXI_AWCACHE),
        .saxigp2_awid({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .saxigp2_awlen(sc_mem_M00_AXI_AWLEN),
        .saxigp2_awlock(sc_mem_M00_AXI_AWLOCK),
        .saxigp2_awprot(sc_mem_M00_AXI_AWPROT),
        .saxigp2_awqos(sc_mem_M00_AXI_AWQOS),
        .saxigp2_awready(sc_mem_M00_AXI_AWREADY),
        .saxigp2_awsize(sc_mem_M00_AXI_AWSIZE),
        .saxigp2_awuser(sc_mem_M00_AXI_AWUSER),
        .saxigp2_awvalid(sc_mem_M00_AXI_AWVALID),
        .saxigp2_bready(sc_mem_M00_AXI_BREADY),
        .saxigp2_bresp(sc_mem_M00_AXI_BRESP),
        .saxigp2_bvalid(sc_mem_M00_AXI_BVALID),
        .saxigp2_rdata(sc_mem_M00_AXI_RDATA),
        .saxigp2_rlast(sc_mem_M00_AXI_RLAST),
        .saxigp2_rready(sc_mem_M00_AXI_RREADY),
        .saxigp2_rresp(sc_mem_M00_AXI_RRESP),
        .saxigp2_rvalid(sc_mem_M00_AXI_RVALID),
        .saxigp2_wdata(sc_mem_M00_AXI_WDATA),
        .saxigp2_wlast(sc_mem_M00_AXI_WLAST),
        .saxigp2_wready(sc_mem_M00_AXI_WREADY),
        .saxigp2_wstrb(sc_mem_M00_AXI_WSTRB),
        .saxigp2_wvalid(sc_mem_M00_AXI_WVALID),
        .saxihp0_fpd_aclk(zynq_ps_pl_clk0));
endmodule
