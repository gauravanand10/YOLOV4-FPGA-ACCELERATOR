# MPSOC_YOLO — YOLOv4-tiny (7 classes) on a custom INT8 RTL accelerator for the ZCU104

A complete, from-scratch hardware implementation of a trained YOLOv4-tiny object detector on the
Xilinx **ZCU104** (Zynq UltraScale+ `xczu7ev-ffvc1156-2-e`). There is no DPU and no HLS: the
accelerator is hand-written SystemVerilog, checked bit-exact against a Python golden model, and built
into a bitstream with Vivado 2024.1. The PS (ARM Cortex-A53, PetaLinux) runs a TCP server. A laptop streams webcam
frames to it and draws the detections that come back.

Classes: `person, car, bicycle, bottle, chair, laptop, cup` · Input 416×416 · Model: AlexeyAB darknet.

---

## 1. Results at a glance

| What | Result | Where it comes from |
|---|---|---|
| Accuracy, float model (mAP@0.5, 500 val images) | **41.19 %** | `02_golden_model/out/map_results.txt` |
| Accuracy, INT8 hardware arithmetic | **41.03 %** (−0.16) | same |
| RTL vs golden, 11-layer feature test | **PASS, bit-exact**, 0–50 % AXI stalls, latency 1–100 | `logs/xsim_feature.log` |
| RTL vs golden, full 416×416 network | **PASS, 948,224 words bit-exact**, 0 AXI errors | `logs/xsim_yolo.log` |
| Post-synthesis gate-level sim (feature test) | **PASS, bit-exact** | `logs/gatesim_feature.log` |
| Cycles per frame (RTL sim) | **7.48 M** | `logs/xsim_yolo.log` |
| Accelerator clock | **187.5 MHz** (PS pl_clk0; 200 MHz is not reachable exactly) | `06_vivado/reports/clock.txt` |
| Accelerator speed | **39.9 ms/frame, about 25 fps** (target was 15–17 fps) | cycles ÷ clock |
| Timing | WNS **+0.099 ns**, WHS **+0.010 ns**, 0 failing endpoints | `06_vivado/reports/timing_impl.rpt` |
| Utilization | 56.7k LUT (24.6 %), 23.6k FF (5.1 %), 96.5 BRAM (30.9 %), 37 DSP (2.1 %) | `06_vivado/reports/utilization_impl.rpt` |
| Power (estimate) | 4.91 W total (PS 2.64 W) | `06_vivado/reports/power.rpt` |
| Bitstream / platform | `yolo_zcu104.bit`, `.bit.bin`, `.xsa` | `06_vivado/out/` |
| On-board test | **not run yet**, see `08_docs/PETALINUX.md` | — |

## 2. How the pieces fit together

```
 00_model  (trained darknet cfg + weights)
     │
     ▼
 02_golden_model  ── float reference ──► calibration ──► INT8 bit-exact model ──► perf model / mAP
     │                                                         │
     ▼                                                         ▼
 03_quant_export  ── yolo_weights.bin, yolo_desc.bin, model_params.h (board)
                  └─ 05_tb/data/*/mem_init.hex + mem_exp.hex (testbench golden DDR images)
     │
     ▼
 04_rtl (SystemVerilog accelerator) ◄──── verified by ──── 05_tb (xsim, bit-exact vs golden)
     │
     ▼
 06_vivado (block design + synth + impl) ──► yolo_zcu104.bit / .bit.bin / .xsa
     │
     ▼
 PetaLinux (08_docs/PETALINUX.md) ──► 07_sw/board/yolo_server  ◄── TCP ──►  07_sw/host/yolo_client.py (laptop webcam)
```

## 3. Directory map

Every folder has its own `README.md` with details.

| Folder | Contents |
|---|---|
| [`00_model/`](00_model/README.md) | Trained YOLOv4-tiny 7-class cfg and weights, plus darknet's reference predictions |
| [`01_dataset/`](01_dataset/README.md) | COCO-2017 7-class subset (8,000 train / 2,000 valid), labels, selection scripts |
| [`02_golden_model/`](02_golden_model/README.md) | Python golden model: darknet parser, float ref, INT8 quantizer, DDR-level HW simulator, perf model, decode/NMS, mAP |
| [`03_quant_export/`](03_quant_export/README.md) | Exporter: binary weights and descriptors for the board, hex DDR images for the testbench |
| [`04_rtl/`](04_rtl/README.md) | The accelerator: 13 synthesizable SystemVerilog/Verilog files |
| [`05_tb/`](05_tb/README.md) | Testbench, AXI memory model, test data, xsim scripts, gate-level flow |
| [`06_vivado/`](06_vivado/README.md) | Vivado 2024.1 build scripts (block design → bitstream → .xsa), reports, outputs |
| [`07_sw/`](07_sw/README.md) | Board application (C, aarch64 Linux) and laptop webcam client (Python) |
| [`08_docs/`](08_docs/README.md) | Full technical report, [architecture](08_docs/ARCHITECTURE.md), [PetaLinux bring-up](08_docs/PETALINUX.md) |
| [`logs/`](logs/README.md) | Every tool log (simulation, Vivado, mAP, copy) |
| [`scripts/`](scripts/README.md) | Helper scripts (asset copy from `E:\yolo_mpsoc`) |
| [`tools/`](tools/README.md) | The Windows darknet build used for training and reference predictions |

## 4. Architecture in one paragraph

The accelerator is a layer-by-layer INT8 convolution engine. The ARM writes a table of 21 descriptors
(one per conv layer) into DDR, points the accelerator at it through AXI-Lite and presses start. For each
layer the accelerator fetches the descriptor, then handles one group of 32 output channels at a time:
1. It loads that group's weights and requantisation parameters into on-chip BRAM.
2. It streams the input feature map row by row from DDR into an 8-row line buffer.
3. A **32×16 PE array (512 INT8 MACs per cycle)** computes one (kernel tap, 16-input-channel chunk) per
   cycle. A per-channel epilogue then applies bias, leaky-ReLU and int8 rounding.
4. The writer stores the 32-channel output pixels back to DDR.

Maxpool (in the loader), 2× upsample and route/concat/group-split (in the writer and in descriptor
addressing) are all fused, so no layer is run on the CPU. Details and diagrams are in
[`08_docs/ARCHITECTURE.md`](08_docs/ARCHITECTURE.md).

## 5. Reproduce everything (Windows PC, Python 3 + torch, Vivado 2024.1)

```bat
cd D:\MPSOC_YOLO\02_golden_model
python calibrate.py            & rem activation scales      -> out\qparams.pkl
python eval_map.py 500         & rem float vs INT8 mAP      -> out\map_results.txt
python check_hwsim.py 3        & rem INT8 model == DDR-level simulator
python perf_model.py           & rem cycles / fps          -> out\perf_model.txt
cd ..\03_quant_export
python export.py               & rem board binaries + testbench hex images
cd ..\05_tb
run_xsim.bat feature 30 3 2    & rem ~20 s, must print PASS
run_xsim.bat yolo 0 40 1       & rem ~60 min, full network, must print PASS
cd ..\06_vivado
build.bat                      & rem ~45 min, needs ~5-6 GB free RAM -> out\*.bit/.xsa
cd ..\07_sw\board
build_board.bat                & rem aarch64 yolo_server -> deploy\
```
Then follow [`08_docs/PETALINUX.md`](08_docs/PETALINUX.md) to boot the board and run the webcam demo.

## 6. Open items
* **Nothing has run on hardware yet.** The next step is `yolo_server --selftest` on the ZCU104.
* **PetaLinux version must match Vivado 2024.1**, the version that made the `.xsa`. See `08_docs/PETALINUX.md` §0.
* **About 2,700 training images had no labels.** `logs/darknet_bad.list` shows darknet looked for their
  labels in `images/train/*.txt`, so they were trained as background. Retraining with fixed label paths
  should raise mAP.
* **Setup slack is thin (+0.1 ns).** If an RTL change breaks timing, pipeline the PE adder tree or the epilogue first.
* **Possible speed-ups:** overlap weight loading with compute (about 5 %), or pack 2 MACs per DSP48 to
  double the array (1,690 DSPs are unused).
