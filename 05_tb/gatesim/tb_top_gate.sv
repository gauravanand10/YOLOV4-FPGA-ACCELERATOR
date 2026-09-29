// GENERATED from ../tb_top.sv by make_tb_gate.py (gate-level flow) - do not edit
// Testbench: loads a golden DDR image, runs the accelerator through AXI-Lite, compares the whole
// DDR image with the golden expected image (descriptor-level Python model).
// plusargs: +DATA=<dir with test.cfg, mem_init.hex, mem_exp.hex>  +RUNS=<n>  +LAT=<rd latency>
//           +STALL=<pct>  +MAXCYC=<timeout>
`timescale 1ns/1ps
module tb_top;
  logic clk = 0, rst_n = 0;
  always #2.5 clk = ~clk;   // 200 MHz

  // AXI-Lite
  logic [7:0]  s_awaddr, s_araddr;
  logic        s_awvalid, s_awready, s_wvalid, s_wready, s_bvalid, s_bready;
  logic        s_arvalid, s_arready, s_rvalid, s_rready;
  logic [31:0] s_wdata, s_rdata;
  logic [3:0]  s_wstrb;
  logic [1:0]  s_bresp, s_rresp;
  // AXI master
  logic [0:0]   awid, arid, bid, rid;
  logic [31:0]  awaddr, araddr;
  logic [7:0]   awlen, arlen;
  logic [2:0]   awsize, arsize, awprot, arprot;
  logic [1:0]   awburst, arburst, bresp, rresp;
  logic         awlock, arlock, awvalid, awready, wlast, wvalid, wready, bvalid, bready;
  logic         arvalid, arready, rlast, rvalid, rready, irq;
  logic [3:0]   awcache, arcache, awqos, arqos;
  logic [127:0] wdata, rdata;
  logic [15:0]  wstrb;

  logic [31:0] base, desc_addr;
  int          num_layers, words, rd_lat = 40, stall_pct = 0, runs = 1;
  longint      maxcyc = 64'd50_000_000;
  string       data_dir;

  yolo_accel_wrap dut (
    .aclk(clk), .aresetn(rst_n),
    .s_axi_awaddr(s_awaddr), .s_axi_awvalid(s_awvalid), .s_axi_awready(s_awready),
    .s_axi_wdata(s_wdata), .s_axi_wstrb(s_wstrb), .s_axi_wvalid(s_wvalid), .s_axi_wready(s_wready),
    .s_axi_bresp(s_bresp), .s_axi_bvalid(s_bvalid), .s_axi_bready(s_bready),
    .s_axi_araddr(s_araddr), .s_axi_arvalid(s_arvalid), .s_axi_arready(s_arready),
    .s_axi_rdata(s_rdata), .s_axi_rresp(s_rresp), .s_axi_rvalid(s_rvalid), .s_axi_rready(s_rready),
    .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
    .m_axi_awburst(awburst), .m_axi_awlock(awlock), .m_axi_awcache(awcache), .m_axi_awprot(awprot),
    .m_axi_awqos(awqos), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
    .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast), .m_axi_wvalid(wvalid), .m_axi_wready(wready),
    .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
    .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
    .m_axi_arburst(arburst), .m_axi_arlock(arlock), .m_axi_arcache(arcache), .m_axi_arprot(arprot),
    .m_axi_arqos(arqos), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
    .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
    .m_axi_rvalid(rvalid), .m_axi_rready(rready), .irq(irq));

  assign bid = '0; assign rid = '0;

  axi_mem_model #(.WORDS_LG(20)) mem (
    .clk, .rst_n, .base, .rd_lat, .stall_pct,
    .awaddr, .awlen, .awsize, .awburst, .awvalid, .awready,
    .wdata, .wstrb, .wlast, .wvalid, .wready, .bresp, .bvalid, .bready,
    .araddr, .arlen, .arsize, .arburst, .arvalid, .arready,
    .rdata, .rresp, .rlast, .rvalid, .rready);

  bit [127:0] exp_mem [0:(1<<20)-1];

  // ---------------- AXI-Lite BFM ----------------
  task automatic axil_write(input logic [7:0] a, input logic [31:0] d);
    @(posedge clk);
    s_awaddr <= a; s_awvalid <= 1; s_wdata <= d; s_wstrb <= 4'hF; s_wvalid <= 1; s_bready <= 1;
    fork
      begin do @(posedge clk); while (!s_awready); s_awvalid <= 0; end
      begin do @(posedge clk); while (!s_wready);  s_wvalid  <= 0; end
    join
    do @(posedge clk); while (!s_bvalid);
    s_bready <= 0;
  endtask

  task automatic axil_read(input logic [7:0] a, output logic [31:0] d);
    @(posedge clk);
    s_araddr <= a; s_arvalid <= 1; s_rready <= 1;
    do @(posedge clk); while (!s_arready);
    s_arvalid <= 0;
    while (!s_rvalid) @(posedge clk);
    d = s_rdata;
    @(posedge clk); s_rready <= 0;
  endtask

  // (gate-level copy: per-layer progress monitor removed, it peeks into the RTL hierarchy)

  // ---------------- test ----------------
  initial begin
    int fd, mism, r;
    logic [31:0] v, cyc, st_row, st_out, wl;
    s_awvalid = 0; s_wvalid = 0; s_bready = 0; s_arvalid = 0; s_rready = 0;
    s_awaddr = 0; s_araddr = 0; s_wdata = 0; s_wstrb = 0;
    if (!$value$plusargs("DATA=%s", data_dir)) data_dir = "data/feature";
    void'($value$plusargs("LAT=%d", rd_lat));
    void'($value$plusargs("STALL=%d", stall_pct));
    void'($value$plusargs("RUNS=%d", runs));
    void'($value$plusargs("MAXCYC=%d", maxcyc));
    fd = $fopen({data_dir, "/test.cfg"}, "r");
    if (fd == 0) $fatal(1, "cannot open %s/test.cfg", data_dir);
    r = $fscanf(fd, "%h %h %h %h", base, desc_addr, num_layers, words);
    $fclose(fd);
    $display("TB: data=%s base=%h desc=%h layers=%0d words=%0d lat=%0d stall=%0d%% runs=%0d",
             data_dir, base, desc_addr, num_layers, words, rd_lat, stall_pct, runs);
    $readmemh({data_dir, "/mem_init.hex"}, mem.mem);
    $readmemh({data_dir, "/mem_exp.hex"}, exp_mem);
    repeat (10) @(posedge clk);
    #200 @(posedge clk);   // gate-level: wait for glbl GSR (100 ns) to end
    rst_n = 1;
    repeat (5) @(posedge clk);
    axil_read(8'h18, v);
    if (v !== 32'h594F4C34) $fatal(1, "bad ID %h", v);
    for (int run = 0; run < runs; run++) begin
      axil_write(8'h08, desc_addr);
      axil_write(8'h0C, num_layers);
      axil_write(8'h00, 32'h3);           // start + irq enable
      fork
        begin wait (irq === 1'b1); end
        begin
          repeat (maxcyc) @(posedge clk);
          $fatal(1, "TIMEOUT after %0d cycles", maxcyc);
        end
      join_any
      disable fork;
      axil_read(8'h04, v);
      axil_read(8'h10, cyc);
      axil_read(8'h1C, st_row);
      axil_read(8'h20, st_out);
      axil_read(8'h24, wl);
      $display("RUN %0d: status=%h cycles=%0d (%.2f ms @200MHz, %.1f fps) stall_rows=%0d stall_out=%0d wload=%0d",
               run, v, cyc, cyc / 200.0e3, 200.0e6 / cyc, st_row, st_out, wl);
      axil_write(8'h04, 32'h2);           // clear done / irq
      repeat (5) @(posedge clk);
      if (irq !== 1'b0) $fatal(1, "IRQ not cleared");
    end
    // compare full DDR image
    mism = 0;
    for (int i = 0; i < words; i++) begin
      if (mem.mem[i] !== exp_mem[i]) begin
        if (mism < 16) $display("MISMATCH word %0d (byte off %h): got %h exp %h", i, i * 16, mem.mem[i], exp_mem[i]);
        mism++;
      end
    end
    $display("AXI: rd_bursts=%0d rd_beats=%0d wr_bursts=%0d wr_beats=%0d protocol_errors=%0d",
             mem.rd_bursts, mem.rd_beats, mem.wr_bursts, mem.wr_beats, mem.errors);
    if (mism == 0 && mem.errors == 0) $display("*** TEST PASSED: %s (%0d words bit-exact) ***", data_dir, words);
    else $display("*** TEST FAILED: %s (%0d mismatching words, %0d protocol errors) ***", data_dir, mism, mem.errors);
    $finish;
  end
endmodule
