# 02_golden_model — Python golden reference (float, INT8, hardware-level) + performance model

This folder defines **what the hardware must compute, bit for bit**. The RTL in `04_rtl` is correct
exactly when its DDR contents after a run equal what `hwprog.simulate()` produces here.

Requirements: Python 3, numpy, torch (CPU or CUDA), opencv-python. Run every script from this folder.

## Modules

| File | Role |
|---|---|
| `darknet_parse.py` | Parses `00_model/cfg/yolov4-tiny-7class-train.cfg` and the `.weights` file (header, per-layer BN params). Folds BN into conv weights/bias as `w·γ/(√var + 1e-6)`, darknet's own formula. `macs()` counts MACs per layer. |
| `float_model.py` | `FloatNet`: float32 forward pass with darknet semantics (route, route groups, maxpool, upsample, leaky 0.1). `load_image()` does darknet preprocessing (RGB, plain resize to 416, no letterbox). |
| `yolo_decode.py` | Head decode with `scale_x_y = 1.05`, anchors and masks, then greedy per-class NMS (IoU 0.45). The same algorithm is ported to C in `07_sw/board/yolo_post.c`. |
| `quant.py` | **INT8 quantizer and bit-exact integer model.** `calibrate()` collects per-layer activation ranges (99.999th percentile). `quantize_network()` builds per-output-channel INT8 weights, int32 bias and `(Mpos, Mneg, sh)`. `int8_forward()` is the integer tensor model. |
| `hwprog.py` | **Hardware program + DDR-level simulator.** Buffer plan, DDR layout (4 KiB aligned), 64-byte binary descriptors, weight blob format, and `simulate()`, which executes the descriptor table on a DDR byte image exactly as the RTL does. `feature_program()` builds the 11-layer random test that exercises every hardware feature. |
| `perf_model.py` | Cycle model per layer and per 32-channel group (weight load, line fill, compute, read efficiency, pipeline depth) → `out/perf_model.txt`. |
| `calibrate.py` | Calibrates on valid images [1000:1100] → `out/qparams.pkl` (quantized weights + scales). |
| `eval_map.py` | mAP@0.5 (VOC all-point, darknet style) of float vs INT8 on valid[0:500] → `out/map_results.*`. |
| `check_hwsim.py` | Proves `int8_forward` == `hwprog.simulate` (both heads, N images). |
| `run_float_demo.py` | Draws float-model detections for a few images (sanity check). |
| `darknet_check/` | `obj_local.data` (D: paths) and `out.txt`. The attempt to run `tools/darknet_win/darknet.exe` failed because its OpenCV DLLs are not in this tree; the float model was instead checked against darknet's saved output (next section). |

## Arithmetic contract (identical in Python, the DDR simulator and the RTL)

```
input      q_in = pixel >> 1                     (uint8 RGB → int8, scale 2/255, padded to 16 channels)
MAC        acc  = Σ  w_q[o][c][ky][kx] · x_q     (int8 × int8, int32 accumulate)
epilogue   t    = sat27(acc + bias32[o])          (saturate to 27-bit signed)
           M    = (t < 0) ? Mneg[o] : Mpos[o]     (Mneg = round(0.1·Mpos) for leaky, = Mpos for linear)
           y    = clamp_int8((t·M + 2^(sh-1)) >>> sh)
```
* Weights are per-output-channel symmetric INT8. The per-input-channel activation scale of the
  producer is folded into the consumer's weights before quantization, so concatenated tensors with
  different scales need no rescaling.
* `Mpos` is normalised into [2^15, 2^16], so it fits the DSP48's 18-bit signed port. `sh` is ≤ 56.
* The two linear head layers output INT8. Their dequant scales (0.2058 and 0.1985) are in
  `03_quant_export/out/model_params.h`.

## Results

**Accuracy** — `out/map_results.txt` (500 validation images, not used for calibration):

| class | float | INT8 |
|---|---|---|
| person | 54.98 | 54.20 |
| car | 37.19 | 36.93 |
| bicycle | 47.81 | 48.90 |
| bottle | 28.28 | 26.62 |
| chair | 27.78 | 27.93 |
| laptop | 65.46 | 66.38 |
| cup | 26.81 | 26.28 |
| **mAP@0.5** | **41.19** | **41.03** |

Raw head correlation float vs INT8: mean 0.9968, min 0.9741. Float model vs darknet on
`000000000074.jpg`: identical detections (bicycle 0.85; persons 0.78 / 0.65 / 0.47 / 0.47 / 0.28).

**Performance model** — `out/perf_model.txt`. Its ms column is computed at 200 MHz; the board runs at 187.5 MHz.

| | cycles | fps @ 187.5 MHz |
|---|---|---|
| Ideal (512 MAC/cycle, 100 % busy) | 6.97 M | 26.9 |
| Modelled (weight loads, fills, 64-cycle read latency, 85 % read efficiency) | 7.57 M | 24.8 |
| RTL simulation (for comparison) | 7.48 M | 25.1 |

Largest layers: L35 (1.24 M cycles), L26 (0.99 M), L18 (0.85 M), L10 (0.80 M), L2 (0.78 M). Average
PE utilisation 91.8 %. DDR traffic: 38.0 MiB read + 6.1 MiB write per frame.

## Outputs (`out/`)
| File | Content |
|---|---|
| `qparams.pkl` | Quantized network (weights, bias, Mpos/Mneg/sh, activation scales). Input to `03_quant_export`. |
| `map_results.txt` / `.json` | Accuracy table above |
| `perf_model.txt` | Per-layer cycle table |

## Run
```bat
python calibrate.py          & rem ~1 min
python eval_map.py 500       & rem ~3-4 min
python check_hwsim.py 3      & rem must print PASS
python perf_model.py
```
