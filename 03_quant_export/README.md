# 03_quant_export — binaries for the board and golden images for the testbench

`export.py` turns the quantized network (`02_golden_model/out/qparams.pkl`) into the exact bytes the
accelerator reads from DDR. It also produces the testbench stimulus and expected results.

```bat
python export.py [image.jpg]     & rem default test image: 01_dataset/images/valid/000000000074.jpg
```

## Board artefacts (`out/`) → copied to `07_sw/board/deploy/`

| File | Size | Content |
|---|---|---|
| `yolo_weights.bin` | 5.96 MB | All 21 layers' parameter + weight blobs, loaded at `DDR_BASE + W_OFF` |
| `yolo_desc.bin` | 1,344 B | 21 descriptors × 64 B, already relocated for `DDR_BASE = 0x7000_0000` |
| `model_params.h` | — | C header: DDR offsets, input size, head offsets and dequant scales, anchors, class names |
| `layout.json` | — | The same layout for Python tools |
| `test_input_rgb.bin` | 519,168 B | 416×416×3 RGB test image |
| `test_heads.bin` | 54,080 B | Expected INT8 head buffers for that image (13×13×64 + 26×26×64) |
| `test_dets.txt` | — | Expected detections (class, score, x1 y1 x2 y2). Used by `yolo_server --selftest`. |

## DDR layout (base 0x7000_0000, inside the 256 MiB reserved region; total 14.5 MiB)

| Offset | Region | Shape (W×H×pixel stride) |
|---|---|---|
| 0x0000_0000 | descriptor table | 21 × 64 B |
| 0x0000_1000 | IN (input image) | 416×416×16 |
| 0x002A_5000 … 0x0089_0000 | feature buffers B0, B1, B8, B6, B16, B14, B24, B22, B34, B26, B27, B28, B35 | see `05_tb/data/yolo/regions.txt` |
| 0x008B_B000 | OUT1 (head 13×13) | 13×13×64 |
| 0x008B_E000 | OUT2 (head 26×26) | 26×26×64 |
| 0x008C_9000 … 0x00E7_8000 | weights W_L0 … W_L36 | 5.96 MB |

The board app uses two input slots and two descriptor tables for double buffering; see `07_sw/board/yolo_accel.c`.

## Descriptor format (16 × uint32, one per conv layer)

| Word | Field |
|---|---|
| w0 | `in_addr`: input buffer base + input channel byte offset (group split / concat source) |
| w1 | `out_addr`: output buffer base + output channel byte offset (concat destination) |
| w2 | `out2_addr`: second destination (used only by L23) |
| w3 | `w_addr`: this layer's weight blob |
| w4 | `in_w \| in_h<<16`: stored input size (before pooling) |
| w5 | `out_w \| out_h<<16`: conv output size (before upsample) |
| w6 | `in_pix_stride \| out_pix_stride<<16` (bytes) |
| w7 | `out2_pix_stride \| cin_chunks<<16 \| cout_groups<<24` |
| w8 | `k[3:0] \| stride[7:4] \| pad[11:8] \| pool_in[12] \| upsample[13] \| out2_en[14]` |
| w9 | `kkcc = k·k·cin_chunks` |
| w10 | bytes per output-channel group = (32 + 32·kkcc)·16 |
| w11 | `conv_in_w \| conv_in_h<<16` (after pooling) |
| w12–w14 | reserved (0) |
| w15 | layer id (debug) |

## Weight blob (per layer, per group g of 32 output channels, at `w_addr + g·w10`)
1. **32 parameter beats** (one 128-bit beat per output channel):
   `[31:0] bias int32 · [63:32] Mpos · [95:64] Mneg · [101:96] sh`.
2. **32·kkcc weight beats**, ordered `[o][tap = ky·k + kx][c]`. Byte i of a beat = W[o][c·16+i][ky][kx].

## Testbench artefacts → `05_tb/data/<test>/`
| File | Content |
|---|---|
| `mem_init.hex` | Initial DDR image as 128-bit words (`@addr` records, zero words skipped) |
| `mem_exp.hex` | Expected DDR image after the run, from the golden descriptor simulator |
| `test.cfg` | `<base> <desc_addr> <num_layers> <words>` (hex) |
| `regions.txt` | Region map (for debugging mismatches) |

Two tests are generated: `feature` (11 random layers, about 29k words) and `yolo` (the full network
on the test image, about 948k words).
