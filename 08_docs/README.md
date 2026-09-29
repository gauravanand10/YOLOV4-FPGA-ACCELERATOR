> **08_docs folder index**
> | File | Content |
> |---|---|
> | `README.md` (this file) | Full technical report: status, results, verification, build notes, board bring-up summary |
> | [`ARCHITECTURE.md`](ARCHITECTURE.md) | Architecture: data layout, buffer plan, micro-architecture, numerics, performance breakdown |
> | [`PETALINUX.md`](PETALINUX.md) | Step-by-step PetaLinux image, SD card, board self-test and webcam demo, plus troubleshooting |
> | `HANDOFF_PROMPT.md`, `HANDOFF_PROMPT_2.md` | Prompts used to continue the work in Claude Code (history) |
>
> The project overview and directory map are in the top-level [`../README.md`](../README.md).
> The detailed board bring-up guide is [`PETALINUX.md`](PETALINUX.md); the short version is at the end of this file.

# YOLOv4-tiny (7-class) custom RTL accelerator for ZCU104

Target: ZCU104, `xczu7ev-ffvc1156-2-e`, Vivado 2024.1. Model: `00_model/cfg/yolov4-tiny-7class-train.cfg`
+ `yolov4-tiny-7class-train_final.weights` (AlexeyAB darknet), 416x416, classes
person car bicycle bottle chair laptop cup.

## Status

| Step | State | Evidence |
|---|---|---|
| 1. Golden model (parser, float ref, calibration, INT8, perf model, exporters, decode/NMS, mAP) | **done, verified** | `02_golden_model/out/`, `logs/map_eval.log` |
| 2. RTL (SystemVerilog) | **done**, Verilator `-Wall` lint clean, xvlog/xelab clean | `04_rtl/` |
| 3. Testbench (AXI memory model, feature test + full network, xsim) | **done, both PASS bit-exact** | `logs/xsim_feature.log`, `logs/xsim_yolo.log` |
| 4. Vivado build (BD, synth, impl, bitstream, .xsa) | **done, timing met** at 187.5 MHz (WNS +0.099 ns, WHS +0.010 ns) | `06_vivado/out/`, `06_vivado/reports/`, `logs/vivado_build.log` |
| 5. Software (board C server, laptop client) | **done**: board app cross-compiles for aarch64 (clean with `-Wall -Wextra`); C decode+NMS == Python; client tested against a PC emulator of the board (`sim_server.py` returns the golden detections) | `07_sw/` |
| 6. Docs | this file | |

Not yet measured on hardware: real DDR bandwidth and end-to-end fps (no board run yet).

## Results

### Accuracy (mAP@0.5, VOC all-point, 500 held-out validation images, calibration on 100 other images)

| class | float | INT8 (bit-exact HW arithmetic) |
|---|---|---|
| person | 54.98 | 54.20 |
| car | 37.19 | 36.93 |
| bicycle | 47.81 | 48.90 |
| bottle | 28.28 | 26.62 |
| chair | 27.78 | 27.93 |
| laptop | 65.46 | 66.38 |
| cup | 26.81 | 26.28 |
| **mAP** | **41.19** | **41.03** (-0.16) |

The float reference was checked against darknet's own output on `000000000074.jpg`: identical detections
(bicycle 0.85; persons 0.78 / 0.65 / 0.47 / 0.47 / 0.28). The float and INT8 heads correlate at 0.997.

### Verification chain (all bit-exact)
1. INT8 tensor model (`quant.int8_forward`) == descriptor-level DDR simulator (`hwprog.simulate`, reads only
   the binary descriptors/weight blob from a DDR byte image): 3 images, both heads identical.
2. RTL == DDR simulator, whole-DDR-image compare in xsim:
   * `feature` test (11 random layers covering stride 2, odd sizes, pool, pooled rows > 8 slots, group split,
     concat, dual destination, upsample, 36->64 head padding, kkcc = 288, 1024-beat rows, 96-byte pixel
     stride crossing 4 KiB, 27-bit and int8 saturation, leaky/linear mix): PASS with 0/30/50 % random AXI
     stalls, read latency 1/3/40/100 cycles, 2 back-to-back runs. A deliberately corrupted expectation is
     detected (negative test).
   * `yolo` full 416x416 network, image 000000000074.jpg: **948,224 words bit-exact, 0 AXI protocol errors**.
3. Board C decode+NMS == Python decode+NMS on the golden head buffers (`test_dets.txt`).

### Performance
The accelerator clock is pl_clk0 = **187.5 MHz** (IOPLL 1500 MHz / 8). The PS PLLs cannot produce exactly
200 MHz with the ZCU104 preset, and an MMCM was deliberately not used (see "Vivado build").

| | cycles | ms @187.5 MHz | fps @187.5 MHz | (fps @200 MHz) |
|---|---|---|---|---|
| ideal (512 MAC/cycle, 100 % busy) | 6.97 M | 37.2 | 26.9 | 28.7 |
| perf model (`02_golden_model/perf_model.py`) | 7.57 M | 40.4 | 24.8 | 26.4 |
| **RTL simulation** (xsim, 40-cycle DDR read latency) | **7.48 M** | **39.9** | **25.1** | 26.7 |

The board app converts the cycle counter using `ACCEL_CLK_HZ` = 187.5 MHz (`07_sw/board/yolo_server.c`).

RTL per-layer cycles match the model to within about 1–3 %. For example, L0: 390,696 simulated vs 390,958
modelled, and L35: 1,234,590 vs 1,236,773. Weight loading is 0.38 M cycles (5 %), and stalls waiting for
input rows are 0.14 M. DDR traffic is about 38 MiB read and 6 MiB written per frame (about 1.2 GB/s at
25 fps, well within HP0).

End-to-end estimate: the board receives 519 KB per frame (about 4.5 ms on GbE), preprocesses it, and
decodes about 1 ms. All of this is double-buffered against the accelerator, so it is expected to be
accelerator-bound at about 20–25 fps. It falls to about 18–21 fps if the software serialises. Either
way that is above the 15–17 fps target. **This has
not been measured on hardware.**

## Architecture (as implemented)
* INT8 weights (per-output-channel, input-channel activation scales folded in) and INT8 activations
  (per-tensor, symmetric), with INT32 accumulation. Input: `pixel >> 1` (scale 2/255), padded to 16 channels.
* Epilogue per channel: `t = sat27(acc + bias)`, `y = clamp8((t*M + 2^(sh-1)) >>> sh)`, where `M` is `Mneg`
  (= round(0.1·Mpos)) for leaky layers when t < 0. Linear layers set `Mneg = Mpos`. The parameters are one
  128-bit beat per channel.
* Feature maps are HWC int8 in DDR. Route, concat and group-split are handled by descriptor `in_addr`
  (channel byte offset) plus pixel stride. Buffer plan: `02_golden_model/hwprog.py::yolo_program`.
* Engine: 32x16 PE array (512 MAC/cycle). For each group of 32 output channels: load params and weights
  (32 banks x 512 x 128b), then stream rows through the 8-slot line buffer (8 x 1024 x 128b). One
  (tap, cin-chunk) is processed per cycle. A pixel only issues when its rows are present and an output-FIFO
  credit is free, so nothing behind the issue stage ever stalls.
* Fused ops: 2x2 maxpool in the line loader, and 2x nearest upsample plus dual-destination write
  (L23 -> B24 and B34) in the writer.
* AXI: an AXI-Lite register block, and one AXI4 128-bit master with bursts of up to 64 beats that never
  cross 4 KiB. Writes are 32-byte bursts, and all B responses are awaited at layer end. Descriptors are
  16 x 32-bit words in DDR (format documented in `hwprog.py`).

Registers (base 0xA000_0000): 0x00 CTRL [0]start [1]irq_en · 0x04 STATUS [0]busy [1]done (W1C) · 0x08 DESC_ADDR ·
0x0C NUM_LAYERS · 0x10 CYCLES · 0x14 CUR_LAYER · 0x18 ID=0x594F4C34 · 0x1C STALL_ROW · 0x20 STALL_OUT · 0x24 WLOAD.

## Folder map / how to reproduce
```
02_golden_model/  darknet_parse.py float_model.py quant.py hwprog.py perf_model.py yolo_decode.py eval_map.py
                  calibrate.py (-> out/qparams.pkl)  check_hwsim.py  run_float_demo.py
03_quant_export/  export.py -> out/{yolo_desc.bin, yolo_weights.bin, model_params.h, layout.json, test_*}
                             -> 05_tb/data/{feature,yolo}/{mem_init.hex, mem_exp.hex, test.cfg}
04_rtl/           yolo_accel.sv (top) + axil_regs, burst_gen, weight_loader, line_loader, conv_engine,
                  pe_array, epilogue, writer, sdp_ram, sync_fifo, yolo_pkg; yolo_accel_wrap.v (BD wrapper)
05_tb/            tb_top.sv, axi_mem_model.sv, run_xsim.bat [test] [stall%] [latency] [runs] [nocompile]
06_vivado/        build.tcl, build.bat  (reports -> 06_vivado/reports, .xsa/.bit -> 06_vivado/out)
07_sw/board/      yolo_server.c yolo_accel.c yolo_post.c, Makefile, build_board.bat (Vitis aarch64 gcc)
07_sw/host/       yolo_client.py (webcam client), sim_server.py (PC emulator of the board)
```
```
cd 02_golden_model && python calibrate.py && python eval_map.py 500 && python check_hwsim.py 3 && python perf_model.py
cd 03_quant_export && python export.py
05_tb\run_xsim.bat feature 30 3 2        (about 20 s)
05_tb\run_xsim.bat yolo 0 40 1           (about 60 min in xsim)
06_vivado\build.bat                      (about 45 min; needs ~5-6 GB free RAM, see below)
06_vivado\build.bat bdonly               (2 min: create + validate the block design only)
06_vivado\build.bat runs                 (reuse prepared project + finished runs; redo only what is missing)
07_sw\board\build_board.bat
```

## Vivado build (06_vivado)

**Outputs:** `06_vivado/out/yolo_zcu104.bit`, `yolo_zcu104.bit.bin` (for `fpgautil`) and
`yolo_zcu104.xsa` (`write_hw_platform -fixed -include_bit`). **Reports:** `06_vivado/reports/`
(`utilization_impl.rpt`, `utilization_hier.rpt`, `timing_impl.rpt`, `power.rpt`, `drc.rpt`, `summary.txt`,
`clock.txt`).

### Block design
| Item | Setting |
|---|---|
| PS | Zynq US+ with the ZCU104 board preset |
| Clock | Everything on pl_clk0 at 187.5 MHz: HPM0/HP0 aclk, SmartConnects, proc_sys_reset and the accelerator |
| Control path | M_AXI_HPM0_FPD (32-bit) -> SmartConnect -> accelerator AXI-Lite at 0xA000_0000 (4 KiB) |
| Data path | Accelerator m_axi (128-bit) -> SmartConnect -> S_AXI_HP0_FPD (128-bit), DDR_LOW only (0-2 GiB) |
| Interrupt | irq -> pl_ps_irq0 |

The script reads back `PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ`. It would keep 200 MHz if the PS could
produce it exactly; otherwise it requests 187.5 MHz. The module reference has no fixed `FREQ_HZ` in
`yolo_accel_wrap.v`. The script copies the pl_clk0 `FREQ_HZ` onto `yolo_accel/aclk`, so
`validate_bd_design` has no clock mismatch. The wrapper drives 1-bit `m_axi_awuser/aruser` = 0, which
matches the 1-bit AxUSER of HP0 (this removes the AWUSER/ARUSER width warning).

### Results (post-route, xczu7ev-ffvc1156-2-e)
| Resource | Whole design | Accelerator only | Available | Util. |
|---|---|---|---|---|
| CLB LUTs | 56,696 | 54,653 | 230,400 | 24.6 % |
| CLB registers | 23,610 | 21,279 | 460,800 | 5.1 % |
| Block RAM tiles (36 Kb) | 96.5 | 96.5 | 312 | 30.9 % |
| URAM | 0 | 0 | 96 | 0 % |
| DSP48E2 | 37 | 37 | 1,728 | 2.1 % |

The BRAM count matches the plan:
* 64 x RAMB36 for the 32 x 512 x 128b weight buffer
* about 29 x RAMB36 for the 8 x 1024 x 128b line buffer
* the rest for the pool row buffer

Vivado mapped the 512 INT8 multipliers to LUTs; the DSPs are used by the epilogue multipliers.
There is plenty of headroom, and the DSP array is still free for a later 2x MAC upgrade.

| Timing / power | Value |
|---|---|
| Clock | 187.5 MHz (5.333 ns) |
| WNS / TNS | **+0.099 ns** / 0.000 (0 failing of 56,989 endpoints) |
| WHS / THS | **+0.010 ns** / 0.000 |
| Pulse width WPWS | +1.166 ns |
| Status | "All user specified timing constraints are met." |
| Total on-chip power | 4.91 W (PS 2.64 W, PL dynamic ~1.57 W, static 0.70 W), Tj 29.8 °C |
| DRC | 73 warnings, 0 errors (DSP pipelining advisories DPIP/DPOP/DPREG, 1 RTSTAT-10) |

Setup slack is small (+0.1 ns). If a future RTL change breaks timing, the first candidates are:
* the PE adder tree
* the epilogue multiply/round
* the line-buffer read path

No pipelining was needed for this build, so the xsim regressions are unchanged.

### Build notes for this 16 GB Windows PC
These notes explain the earlier failures.
* **Two Vivado sessions.** `build.bat` runs stage 1 "prep" (project, BD, validate, generate, wrapper),
  then stage 2 "runs" (synth, impl, bitstream, reports, .xsa) in a fresh process. The BD session (~3 GB)
  is therefore not resident during implementation.
* **Memory settings.**
  * The BD is synthesised globally (`synth_checkpoint_mode None`), so there are no per-IP OOC runs.
  * `general.maxThreads 4` in the parent.
  * The synth pre-hook `lowmem_pre.tcl` sets 1 helper process; by default there are 4 helpers of ~2 GB each.
  * The impl pre-hook `lowmem_impl_pre.tcl` sets 2 threads for place.
  * Runs use `-jobs 2`.
  * Peak memory: synth ~4.8 GB, impl ~4-5 GB. Close VS Code/browsers/Docker first; `wsl --shutdown` frees the WSL VM.
* **No clk_wiz.** Creating one crashed Vivado (`Failed to create IP instance`, then EXCEPTION_BREAKPOINT)
  when free memory was low.
* **Antivirus.** McAfee plus Defender real-time scanning sometimes make Vivado fail to open its own Tcl
  files ("couldn't read file ... no such file or directory" for files that exist). `build.bat` retries
  such runs up to 3 times. The permanent fix is to exclude `C:\Xilinx` and `D:\MPSOC_YOLO` from scanning.
* **Failure detection.** `build.bat` reports failure on any of:
  * a non-zero Vivado exit code
  * any `ERROR:` line
  * a missing `BUILD DONE` marker
  * a missing `.bit` or `.xsa`

  `build.tcl` itself stops with an error if WNS or WHS is negative.
* **RTL fix found by synthesis.** `sdp_ram.sv` used a string parameter inside `(* ram_style = ... *)`.
  xsim and Verilator accept that, but Vivado synthesis does not (Synth 8-281). It is now the literal
  `"block"`. The feature regression still passes bit-exact (30 % stalls, latency 3, 2 runs).

## Board bring-up (PetaLinux 2024.1, on a Linux host or WSL)
1. **Create the project from the .xsa**
   ```
   petalinux-create -t project --template zynqMP -n yolo_plnx && cd yolo_plnx
   petalinux-config --get-hw-description=<path>/06_vivado/out/yolo_zcu104.xsa
   ```
   In the menu, choose Image Packaging -> root filesystem type EXT4 (SD card), or keep INITRD.
2. **Reserve 256 MiB of DDR at 0x7000_0000 for the accelerator.** This holds the weights, descriptors,
   feature maps and input/head buffers. Edit
   `project-spec/meta-user/recipes-bsp/device-tree/files/system-user.dtsi`:
   ```
   /include/ "system-conf.dtsi"
   / {
       reserved-memory {
           #address-cells = <2>; #size-cells = <2>; ranges;
           yolo_reserved: yolo@70000000 { reg = <0x0 0x70000000 0x0 0x10000000>; no-map; };
       };
   };
   ```
   The board app maps this region and the registers (0xA000_0000, 4 KiB) through `/dev/mem`. Run
   `petalinux-config -c kernel` and make sure `CONFIG_STRICT_DEVMEM` is off, or at least that
   `CONFIG_IO_STRICT_DEVMEM` is off. The region is `no-map`, so Linux never uses it.
3. **Enable fpgautil** if you want to (re)load the bitstream at runtime: `petalinux-config -c rootfs` ->
   Filesystem Packages -> base -> fpga-manager-script. Then build and package:
   ```
   petalinux-build
   petalinux-package --boot --fsbl images/linux/zynqmp_fsbl.elf --u-boot --pmufw images/linux/pmufw.elf \
       --fpga images/linux/system.bit --force
   ```
   Copy `images/linux/BOOT.BIN`, `boot.scr` and `image.ub` to the SD card's FAT partition (and the rootfs
   to the EXT4 partition if you chose EXT4). Set the ZCU104 boot switches to SD and boot.
4. **Load the bitstream.** Skip this if BOOT.BIN already contains it via `--fpga`. Otherwise, or to reload:
   ```
   fpgautil -b yolo_zcu104.bit.bin          # copied from 06_vivado/out/
   ```
   The .bin is made with `bootgen -image bit2bin.bif -arch zynqmp -process_bitstream bin`, where
   `bit2bin.bif` is `all:{ yolo_zcu104.bit }`. Check that the accelerator answers:
   `devmem 0xA0000018` must return `0x594F4C34` ("YOL4").
5. **Self-test on the board.** From the laptop: `scp -r 07_sw/board/deploy root@<board-ip>:/home/root/yolo`.
   Then on the board:
   ```
   cd /home/root/yolo
   ./yolo_server --selftest .      # both input slots must print PASS (bit-exact heads) + accel ms / fps
   ```
   The expected accelerator time is about 7.5 M cycles, roughly 40 ms, about 25 fps at 187.5 MHz.
6. **Run the server:** `./yolo_server -p 5000 -m . -t 0.25`.
7. **Laptop webcam client:** the laptop and the board must be on the same network (the ZCU104 GbE port,
   for example a direct cable with static IPs 192.168.1.10 on the board and 192.168.1.1 on the laptop).
   ```
   pip install opencv-python numpy
   python 07_sw/host/yolo_client.py --host <board-ip> --port 5000 --cam 0
   ```
   The client draws the boxes with end-to-end FPS, accelerator time and detection count; press `q` to quit. Without a board,
   `python 07_sw/host/sim_server.py --port 5000` emulates the board on the PC with the bit-exact INT8
   model, at about 0.2 s per frame. Point the client at `--host 127.0.0.1`.

## Notes / open items
* `logs/darknet_bad.list` lists 4,035 entries: training images whose label files darknet could not find,
  because it looked for `images/train/*.txt` while labels live in `labels/train`. Those images were trained
  as background, so retraining with corrected label paths would probably raise mAP.
* The measured MAC count is 3.40 GMAC/frame (3.56 G including channel padding), not the ~3.49 quoted in
  the original spec.
* Possible performance upgrades: overlap next-group weight loading with compute (−5 % cycles), and use
  2 MACs per DSP48 packing.
