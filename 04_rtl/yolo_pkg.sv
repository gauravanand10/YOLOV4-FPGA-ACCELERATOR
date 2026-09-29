// YOLOv4-tiny accelerator - shared parameters and descriptor type.
package yolo_pkg;
  localparam int AW      = 32;     // AXI address width
  localparam int DW      = 128;    // AXI data width (one 16-channel chunk)
  localparam int NOC     = 32;     // output channels per group (PE rows)
  localparam int NIC     = 16;     // input channels per chunk  (PE cols)
  localparam int LB_SLOTS_LG = 3;  // 8-row line buffer
  localparam int LB_ROW_LG   = 10; // 1024 beats per row slot
  localparam int WB_DEPTH_LG = 9;  // 512 weight beats per output channel
  localparam int OFIFO_LG    = 4;  // 16-pixel output FIFO (credits)
  localparam logic [31:0] ACCEL_ID = 32'h594F_4C34; // "YOL4"

  typedef struct packed {
    logic [31:0] in_addr;
    logic [31:0] out_addr;
    logic [31:0] out2_addr;
    logic [31:0] w_addr;
    logic [15:0] in_w, in_h;          // stored input dims
    logic [15:0] out_w, out_h;        // conv output dims (pre-upsample)
    logic [15:0] in_ps, out_ps, out2_ps;
    logic [7:0]  cc;                  // input chunks
    logic [7:0]  ngrp;                // output groups
    logic [3:0]  k, s, pad;
    logic        pool, ups, out2_en;
    logic [15:0] kkcc;
    logic [31:0] grp_bytes;
    logic [15:0] in_wc, in_hc;        // conv input dims (post-pool)
  } desc_t;

  function automatic desc_t unpack_desc(input logic [511:0] d);
    desc_t r;
    r.in_addr   = d[0*32 +: 32];
    r.out_addr  = d[1*32 +: 32];
    r.out2_addr = d[2*32 +: 32];
    r.w_addr    = d[3*32 +: 32];
    r.in_w      = d[4*32 +: 16];  r.in_h   = d[4*32+16 +: 16];
    r.out_w     = d[5*32 +: 16];  r.out_h  = d[5*32+16 +: 16];
    r.in_ps     = d[6*32 +: 16];  r.out_ps = d[6*32+16 +: 16];
    r.out2_ps   = d[7*32 +: 16];  r.cc     = d[7*32+16 +: 8];  r.ngrp = d[7*32+24 +: 8];
    r.k         = d[8*32 +: 4];   r.s      = d[8*32+4 +: 4];   r.pad  = d[8*32+8 +: 4];
    r.pool      = d[8*32+12];     r.ups    = d[8*32+13];       r.out2_en = d[8*32+14];
    r.kkcc      = d[9*32 +: 16];
    r.grp_bytes = d[10*32 +: 32];
    r.in_wc     = d[11*32 +: 16]; r.in_hc  = d[11*32+16 +: 16];
    return r;
  endfunction

  // per-byte signed max of two 16 x int8 beats
  function automatic logic [127:0] vmax8(input logic [127:0] a, input logic [127:0] b);
    logic [127:0] r;
    for (int i = 0; i < 16; i++)
      r[8*i +: 8] = ($signed(a[8*i +: 8]) > $signed(b[8*i +: 8])) ? a[8*i +: 8] : b[8*i +: 8];
    return r;
  endfunction
endpackage
