# Continue: custom RTL YOLOv4-tiny accelerator on ZCU104

Workspace: D:\MPSOC_YOLO (do ALL work here). Original project (read-only source): E:\yolo_mpsoc.
Vivado 2023.x installed at C:\Xilinx (Windows). Target board: ZCU104 (xczu7ev-ffvc1156-2-e).

## State so far
- Folder tree created: 00_model/{cfg,weights,darknet_predictions}, 01_dataset/scripts, 02_golden_model,
  03_quant_export, 04_rtl, 05_tb, 06_vivado, 07_sw/{board,host}, 08_docs, tools/darknet_win, logs, scripts.
- scripts\copy_from_E.bat was launched to robocopy E:\yolo_mpsoc -> D:\MPSOC_YOLO (models, weights, predictions,
  scripts, full dataset, darknet.exe). Check logs\copy.done / logs\copy.log; re-run the .bat if incomplete.
- Nothing else written yet.

## Model facts
- Use cfg yolov4-tiny-7class-train.cfg + weights yolov4-tiny-7class-train_final.weights (AlexeyAB darknet).
  NOTE yolov4_tiny_7class.cfg is actually the stock 80-class cfg - do not use.
- 416x416x3 input, classes: person car bicycle bottle chair laptop cup. Heads: 13x13 (mask 3,4,5 anchors
  81,82 135,169 344,319) and 26x26 (mask 0,1,2 anchors 10,14 23,27 37,58); 36 filters = 3x(5+7);
  scale_x_y=1.05, leaky 0.1, BN folded as w*scale/(sqrt(var)+1e-6). Darknet resizes (no letterbox).
- ~3.49 GMAC/frame. logs\darknet_bad.list shows ~2.7k train images whose labels darknet could not find
  (it looked in images/train/*.txt) - flag to user, maybe retrain later.

## Chosen architecture (implement this)
- INT8 weights (per-output-channel) / INT8 activations (per-channel scale vectors allowed, folded into weights),
  INT32 accumulate. Epilogue per channel: t=acc+bias32, clamp to 27b, y=(t*M + round)>>>sh, M=M_pos or
  M_neg(=round(0.1*M_pos)) when leaky and t<0; clamp [-128,127]. Params per channel packed in one 128b beat.
- Feature maps in DDR, HWC layout, 16-byte (128b) chunks; descriptor fields pix_stride + channel offset give
  route/concat and group-split (groups=2,group_id=1) for free. Input image padded to 16 channels.
- Engine: PE array 32 out-ch x 16 in-ch = 512 INT8 MACs @ 200 MHz. Per output pixel loop over cin_chunks x K*K
  taps (1 cycle each), accumulators double-buffered, epilogue pipelined. Loop per layer: for each 32-oc group:
  load params+weights (weight buffer 32 banks x 128b x 512 deep), then stream input rows through an 8-slot
  line buffer (8x1024x128b, slot=iy%8, addr=slot*1024+x*cin_chunks+c) while computing.
- Fused ops: 2x2/s2 maxpool applied in the line-buffer loader (pool_in flag); 2x nearest upsample in writer
  (L32); dual-destination write (L23 -> concat buf [L18|L23] and [L33up|L23]). Heads padded to 64 ch.
- AXI: AXI-Lite slave (CTRL/STATUS/DESC_ADDR/NUM_LAYERS/cycle counter/IRQ), one AXI4 128b master to
  S_AXI_HP0_FPD; bursts <=64 beats, no 4KB crossing; writes = 32B bursts per pixel via FIFO; wait all B
  responses at layer end. Descriptor table in DDR, fetched per layer.
- Buffer plan: B8[104x104x128]=[L2|L7], B6=[L5|L4], B16=[L10|L15], B14=[L13|L12], B24=[L18|L23],
  B22=[L21|L20], B34=[L33up|L23] (384ch), B26,B27,B28, OUT1 13x13x64, OUT2 26x26x64.
- Target: ~6.9M ideal cycles -> ~29 fps compute-bound, 15-20 fps end-to-end with overheads (match the
  user's 15-17 fps). Golden model must include a cycle/perf model reporting fps per layer.

## Remaining work (in order)
1. 02_golden_model (Python/numpy): darknet cfg+weights parser, float reference, calibration on ~100 valid
   images, INT8 bit-exact model identical to RTL arithmetic, perf model, exporters (weight blob, descriptor
   table, DDR image hex, expected outputs), YOLO decode + NMS, float vs INT8 mAP on a valid subset.
2. 04_rtl (SystemVerilog, synthesizable, Verilator + Vivado clean): top, axi_lite regs, axi master,
   desc fetch, weight loader/buffer, line loader (pool), PE array + adder trees, epilogue, writer.
3. 05_tb: SV testbench with AXI memory model ($readmemh DDR image), small feature-coverage net + full
   416 network bit-exact vs golden (Verilator), plus xsim run scripts.
4. 06_vivado: build.tcl - project for ZCU104, block design (Zynq US+ PS preset, pl_clk0 200 MHz, HPM0 ->
   AXI-Lite, HP0 <- master, IRQ), RTL as module reference, synth, impl, bitstream, write_hw_platform .xsa,
   utilization/timing reports. Run via a .bat: C:\Xilinx\Vivado\<ver>\bin\vivado.bat -mode batch -source ...
   logging to D:\MPSOC_YOLO\logs.
5. 07_sw: board C app (PetaLinux, /dev/mem or UIO, reserved DDR, TCP server, preprocess, start accel,
   decode+NMS, double-buffered frames) and laptop Python webcam client (OpenCV capture, resize 416,
   send raw RGB, draw boxes, show FPS).
6. 08_docs: README + architecture doc, verification results, utilization/timing, fps.

Do not modify E:\yolo_mpsoc. Verify every step (sim pass, timing met, fps estimate) before reporting done.
