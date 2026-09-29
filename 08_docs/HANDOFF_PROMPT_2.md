Continue my ZCU104 YOLOv4-tiny custom RTL accelerator project. Work ONLY in D:\MPSOC_YOLO
(E:\yolo_mpsoc is the read-only original). Vivado/Vitis 2024.1 are installed under C:\Xilinx (Windows,
16 GB RAM, i5-13420H). The previous Claude Code chat was lost after a PC crash. Read these first:
08_docs\README.md, 08_docs\HANDOFF_PROMPT.md, 02_golden_model\out\perf_model.txt,
02_golden_model\out\map_results.txt, 06_vivado\build.tcl, 06_vivado\build.bat, logs\vivado_build*.log.

ALREADY DONE AND VERIFIED (do not redo unless something is broken):
- 00_model / 01_dataset: copied from E:, including cfg, weights (use yolov4-tiny-7class-train.cfg + _final.weights) and dataset.
- 02_golden_model: darknet parser, float model, calibration, bit-exact INT8 model (quant.py), eval_map.py, perf_model.py, yolo_decode.py.
  mAP@0.5 on 500 valid images is 41.19 float vs 41.03 INT8. The perf model gives 7.57M cycles, which is 26.4 fps at 200 MHz.
- 03_quant_export: yolo_weights.bin, yolo_desc.bin, layout.json, model_params.h, test_input_rgb.bin, test_heads.bin, test_dets.txt.
- 04_rtl: yolo_pkg, axil_regs, burst_gen, weight_loader, line_loader, pe_array (32x16 = 512 INT8 MAC),
  epilogue, writer, conv_engine, sdp_ram, sync_fifo, yolo_accel.sv, and yolo_accel_wrap.v (the Verilog wrapper used as the BD module reference).
- 05_tb: tb_top.sv + axi_mem_model.sv + run_xsim.bat.
  The feature test (11 layers) PASSED bit-exact with stalls.
  The full 416x416 network PASSED bit-exact (948224 words) in xsim: 7.48M cycles, 37.4 ms, 26.7 fps, 0 AXI protocol errors.
- 07_sw: board/ (yolo_server.c, yolo_accel.c/h, yolo_post.c/h, Makefile, build_board.bat, --selftest mode)
  and host/ (yolo_client.py webcam client, sim_server.py golden-model stand-in).

WHAT FAILED - fix this now: the Vivado build in 06_vivado (block design: Zynq US+ PS ZCU104 preset,
yolo_accel_wrap module reference, smartconnects, AXI-Lite on HPM0, 128b master on S_AXI_HP0_FPD).
1) Early runs failed validate_bd_design with FREQ_HZ mismatches: pl_clk0 came out at 187.5 MHz but the
   accelerator was declared at 200 MHz.
2) A clk_wiz was then added. The last run crashed with "Failed to create IP instance system_clk_wiz_200_0",
   followed by EXCEPTION_BREAKPOINT (hs_err_pid31132). Available virtual memory was only about 2.4 GB, and the
   PC then crashed, so this was probably out of memory.
3) build.bat wrongly prints "VIVADO BUILD OK" even when Vivado fails.
No synthesis, reports, .bit or .xsa exist yet.

TASKS:
a) Clean start: delete 06_vivado\proj, 06_vivado\.Xil and 06_vivado\hs_err_* (keep the logs and move old logs to logs\old).
b) Make the clock robust. Preferred: no clk_wiz. Use pl_clk0 at whatever the PS really gives (read it back with
   get_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ) and propagate FREQ_HZ to the module
   reference ports with the X_INTERFACE_PARAMETER attributes in yolo_accel_wrap.v, or set the property on the
   BD pins, so validate_bd_design passes. Target 200 MHz if the PS can generate it exactly, otherwise 187.5 MHz
   (about 24.7 fps, still above the 15-17 fps target). Also tie off or match the HP0 AWUSER/ARUSER width warning.
c) Keep memory low: set_param general.maxThreads 4. Use a synth_design/opt/place/route flow via launch_runs -jobs 2.
   Close other apps before running.
d) Fix build.bat so it checks the Vivado exit code AND that the .bit exists before printing OK, and logs to D:\MPSOC_YOLO\logs.
e) Run synth, impl and bitstream, then write_hw_platform -include_bit to produce yolo_zcu104.xsa. Save
   utilization, timing_summary (WNS must be >= 0) and power reports to 06_vivado\reports, and copy the .bit/.xsa to 06_vivado\out.
   If timing fails, add pipeline registers in the adder tree / epilogue / line-buffer read path, re-run the
   full xsim regression (05_tb\run_xsim.bat for both the feature and yolo data) to stay bit-exact, then rebuild.
f) Build the board app (07_sw\board\build_board.bat) and fix the sim_server.py MemoryError (it converts to
   float64 - use int32/float32 and reuse buffers).
g) Update 08_docs\README.md with final utilization, timing, measured sim fps, and step-by-step board bring-up
   (PetaLinux from the .xsa, reserved-memory 0x70000000 256 MiB, fpgautil, yolo_server --selftest, then yolo_client.py with the laptop webcam).
Verify each step from the logs before saying it is done. Do not modify E:\yolo_mpsoc.
