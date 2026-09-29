@echo off
REM Rebuilds the history of D:\MPSOC_YOLO\github as a series of logical commits (files are NOT changed).
REM After it finishes:  git push -u origin main --force
setlocal
cd /d D:\MPSOC_YOLO\github || exit /b 1
git checkout -q --orphan history || exit /b 1
git rm -r -q --cached . >nul

call :c "Initialize repository: gitignore and gitattributes" .gitignore .gitattributes
call :c "Add YOLOv4-tiny 7-class darknet configs" 00_model/cfg
call :c "Add pretrained backbone and final trained 7-class weights" 00_model/weights
call :c "Add darknet reference predictions on validation images" 00_model/darknet_predictions
call :c "Document the trained model and layer table" 00_model/README.md
call :c "Dataset: class list and COCO 7-class image selection" 01_dataset/classes.names 01_dataset/scripts/prepare_coco_7class.py 01_dataset/scripts/select_coco_7class.py
call :c "Dataset: balanced 8k/2k COCO subset (seed 42)" 01_dataset/scripts/select_balanced_coco.py 01_dataset/selected_train_ids.txt 01_dataset/selected_valid_ids.txt
call :c "Dataset: COCO download and YOLO label conversion" 01_dataset/scripts/download_convert_coco.py 01_dataset/train.txt 01_dataset/valid.txt
call :c "Dataset: prediction script, README and unlabeled-image list" 01_dataset/scripts/save_10_predictions.ps1 01_dataset/README.md logs/darknet_bad.list
call :c "Golden model: darknet cfg/weights parser with BN folding" 02_golden_model/darknet_parse.py
call :c "Golden model: float reference forward pass" 02_golden_model/float_model.py 02_golden_model/run_float_demo.py 02_golden_model/darknet_check
call :c "Golden model: YOLO head decode and greedy NMS" 02_golden_model/yolo_decode.py
call :c "Golden model: INT8 quantizer and bit-exact integer model" 02_golden_model/quant.py
call :c "Golden model: calibrate activation scales, save quantized params" 02_golden_model/calibrate.py 02_golden_model/out/qparams.pkl
call :c "Evaluate float vs INT8 mAP@0.5 : 41.19 vs 41.03" 02_golden_model/eval_map.py 02_golden_model/out/map_results.json 02_golden_model/out/map_results.txt logs/map_eval.log
call :c "Golden model: hardware program, descriptors and DDR-level simulator" 02_golden_model/hwprog.py
call :c "Verify INT8 model == DDR simulator (bit-exact)" 02_golden_model/check_hwsim.py
call :c "Add cycle-level performance model (7.57 M cycles/frame)" 02_golden_model/perf_model.py 02_golden_model/out/perf_model.txt
call :c "Document the golden model and arithmetic contract" 02_golden_model/README.md
call :c "Export board binaries and testbench DDR images" 03_quant_export/export.py 03_quant_export/out
call :c "Document export formats, DDR layout and descriptors" 03_quant_export/README.md
call :c "RTL: package, dual-port RAM and FIFO primitives" 04_rtl/yolo_pkg.sv 04_rtl/sdp_ram.sv 04_rtl/sync_fifo.sv
call :c "RTL: AXI4-Lite control and status registers" 04_rtl/axil_regs.sv
call :c "RTL: AXI burst generator and weight loader" 04_rtl/burst_gen.sv 04_rtl/weight_loader.sv
call :c "RTL: line loader with fused 2x2 maxpool" 04_rtl/line_loader.sv
call :c "RTL: 32x16 INT8 PE array (512 MAC/cycle)" 04_rtl/pe_array.sv
call :c "RTL: 32-lane requantization epilogue" 04_rtl/epilogue.sv
call :c "RTL: convolution engine pipeline with credit flow control" 04_rtl/conv_engine.sv
call :c "RTL: output writer with upsample and dual destination" 04_rtl/writer.sv
call :c "RTL: accelerator top, control FSM and block-design wrapper" 04_rtl/yolo_accel.sv 04_rtl/yolo_accel_wrap.v
call :c "Document the RTL micro-architecture and register map" 04_rtl/README.md
call :c "TB: AXI4 memory model with protocol checker" 05_tb/axi_mem_model.sv
call :c "TB: bit-exact top-level testbench and xsim script" 05_tb/tb_top.sv 05_tb/files.f 05_tb/files_sim.f 05_tb/run_xsim.bat
call :c "TB: feature test vectors (11 layers)" 05_tb/data
call :c "TB: post-synthesis gate-level simulation flow" 05_tb/gatesim
call :c "Add simulation logs: feature, full network and gate-level PASS" logs/xvlog.log logs/xelab.log logs/xsim_feature.log logs/xsim_feature_neg.log logs/xsim_yolo.log logs/gatesim_feature.log logs/netlist_check.log
call :c "Document verification method and results" 05_tb/README.md
call :c "Vivado: scripted ZCU104 build with low-memory flow" 06_vivado/build.tcl 06_vivado/build.bat 06_vivado/lowmem_pre.tcl 06_vivado/lowmem_impl_pre.tcl
call :c "Vivado: post-route reports, timing met at 187.5 MHz" 06_vivado/reports logs/vivado_prep.log logs/vivado_build.log
call :c "Vivado: bitstream, bit.bin and XSA" 06_vivado/out
call :c "Document the Vivado build and results" 06_vivado/README.md
call :c "Board app: /dev/mem driver, YOLO decode and TCP server" 07_sw/board/yolo_accel.c 07_sw/board/yolo_accel.h 07_sw/board/yolo_post.c 07_sw/board/yolo_post.h 07_sw/board/yolo_server.c 07_sw/board/model_params.h 07_sw/board/Makefile 07_sw/board/build_board.bat
call :c "Board app: aarch64 build and deploy package" 07_sw/board/deploy 07_sw/board/README.md
call :c "Host: laptop webcam client and board emulator" 07_sw/host 07_sw/README.md
call :c "PetaLinux 2024.1: project config and reserved-memory device tree" 08_petalinux/project-spec
call :c "PetaLinux 2024.1: boot images with accelerator bitstream" 08_petalinux/images 08_petalinux/README.md
call :c "Docs: diagrams, charts and Vivado screenshots" docs/images
call :c "Docs: architecture and board bring-up guides" docs/README.md docs/ARCHITECTURE.md docs/PETALINUX.md logs/README.md
call :c "Add project README" README.md

git add -A
git diff --cached --quiet || git commit -q -m "Add remaining files"
git branch -D main >nul 2>&1
git branch -m main
echo.
echo ===== commits:
git rev-list --count HEAD
git status --short
echo Now push with:  git push -u origin main --force
exit /b 0

:c
set "MSG=%~1"
shift
:addloop
if "%~1"=="" goto docommit
git add -- "%~1"
shift
goto addloop
:docommit
git commit -q -m "%MSG%" && echo [ok] %MSG%
exit /b 0
