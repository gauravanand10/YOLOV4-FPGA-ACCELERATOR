# Architecture — YOLOv4-tiny INT8 accelerator on the ZCU104

## 1. Design goals and the choices they led to

| Goal | Choice |
|---|---|
| ≥ 15–17 fps at 416×416 (3.40 GMAC/frame) | 512 INT8 MAC/cycle at ~190–200 MHz → 26.9 fps ideal, **25.1 fps simulated** at 187.5 MHz |
| Keep float accuracy | INT8 per-output-channel weights, INT32 accumulation, per-channel requantisation → mAP 41.03 vs 41.19 |
| Run the **whole** network in PL (no CPU layers) | Route, concat, group-split, maxpool and upsample are fused into addressing, the loader and the writer |
| Simple, verifiable hardware | One generic conv engine driven by a descriptor table; a Python model defines every bit |
| Fit a ZCU104 comfortably and close timing | 24.6 % LUT, 30.9 % BRAM, 2 % DSP, WNS +0.099 ns |

## 2. System view

```
  ┌──────────────── PS (4× Cortex-A53, PetaLinux) ─────────────────┐        ┌────────── PL ─────────┐
  │ yolo_server:  TCP rx → preprocess (pixel>>1, 16-ch HWC) ──┐    │ HPM0   │ yolo_accel            │
  │               start/poll via /dev/mem  ───────────────────┼────┼───────►│  AXI-Lite registers   │
  │               decode + NMS ◄── heads (13², 26² × 64 ch)   │    │        │                       │
  └───────────────────────────────────────────────────────────┼────┘        │  AXI4 master 128b     │
                                                              ▼             └──────────┬────────────┘
  DDR4 (PS)   0x7000_0000 reserved 256 MiB:                                            │ HP0
     descriptors · input slots A/B · feature buffers · heads · weights (5.96 MB)  ◄────┘
```
The accelerator never touches the CPU caches, because HP0 is not coherent. The CPU uses a non-cached
mapping of the reserved region.

## 3. Execution model

1. The CPU writes 21 descriptors (one per conv layer), the weights (once) and the input image.
2. It writes DESC_ADDR and NUM_LAYERS, then CTRL.start.
3. For each layer:
   * Fetch the 64-byte descriptor.
   * For each group of 32 output channels:
     1. **Weight load:** 32 parameter beats plus 32·kkcc weight beats go into 32 BRAM banks. Compute is idle during this (5 % of runtime).
     2. **Stream:** the line loader fetches input rows into an 8-row circular line buffer. The engine
        issues one (tap, input-chunk) per cycle to the 32×16 PE array. Finished pixels go through the
        epilogue to the writer, then to DDR. All three run concurrently.
   * Wait until every write is acknowledged, because the next layer reads these results.
4. STATUS.done is set. The CPU reads the two head buffers and decodes them.

## 4. Data layout — how routes and concats become free

Feature maps are **HWC int8** in DDR:
`addr = base + (y·W + x)·pixel_stride + channel`. One 128-bit AXI beat = 16 consecutive channels of one pixel.

* **Concat** (`route a,b`): both producers write into the *same* buffer with a wide pixel stride and
  different channel offsets. For example L2 writes channels 0–63 of B8 and L7 writes channels 64–127.
  No copy is needed.
* **Group split** (`route groups=2 group_id=1`): the consumer reads the same buffer starting at channel
  offset C/2. For example L4 reads B8 + 32 bytes.
* **Two consumers of one tensor:** L23 writes to B24 (for L26) *and* B34 (for L35) in the same pass
  (the writer's second destination).
* **Upsample ×2:** L32's writer writes each pixel to a 2×2 block of B34.
* **Maxpool 2×2/s2:** done while loading. Each conv input row is max(row 2r, row 2r+1) with horizontal pairs maxed.

### Buffer plan (all 4 KiB aligned)

| Buffer | W×H×stride | Written by | Read by |
|---|---|---|---|
| IN | 416×416×16 | CPU | L0 |
| B0 | 208×208×32 | L0 | L1 |
| B1 | 104×104×64 | L1 | L2 |
| B8 | 104×104×128 | L2 (ch 0–63), L7 (64–127) | L4 (ch 32–63), L10 (all, pooled) |
| B6 | 104×104×64 | L5 (0–31), L4 (32–63) | L5 (32–63), L7 (all) |
| B16 | 52×52×256 | L10 (0–127), L15 (128–255) | L12 (64–127), L18 (all, pooled) |
| B14 | 52×52×128 | L13 (0–63), L12 (64–127) | L13 (64–127), L15 (all) |
| B24 | 26×26×512 | L18 (0–255), L23 (256–511) | L20 (128–255), L26 (all, pooled) |
| B22 | 26×26×256 | L21 (0–127), L20 (128–255) | L21 (128–255), L23 (all) |
| B34 | 26×26×384 | L32 upsampled (0–127), L23 (128–383) | L35 |
| B26 / B27 / B28 | 13×13×512 / 256 / 512 | L26 / L27 / L28 | L27 / L28 + L32 / L29 |
| B35 | 26×26×256 | L35 | L36 |
| OUT1 / OUT2 | 13×13×64 / 26×26×64 | L29 / L36 (36 channels used) | CPU |

## 5. Micro-architecture

```
 DDR ──► burst_gen ──► line_loader ──(pool)──► LINE BUFFER 8 slots × 1024 × 128b  ─┐ 16 activations
 DDR ──► burst_gen ──► weight_loader ─────────► WEIGHT BANKS 32 × 512 × 128b ──────┤ 32×16 weights
                                   └──────────► PARAMS 32 × 128b                    │
                                                                                    ▼
      issue (oy,ox,ky,kx,c) ─► address ─► BRAM (2) ─► PE ARRAY 32×16 (3) ─► ACC ×32 ─► EPILOGUE ×32 (5)
                                                                                    │
                                          writer ◄── output FIFO 16 × 256b ◄────────┘
                                            └──► DDR (32-B bursts; ×4 upsample; 2nd destination)
```

| Unit | Size | Why |
|---|---|---|
| PE array | 32 output × 16 input channels = 512 MAC | 16 channels = one 128-bit beat; 32 outputs = one 256-bit output pixel = 2 beats |
| Weight banks | 32 × 512 × 128 b = 256 KB (64 RAMB36) | largest group: kkcc = 9 × 32 = 288 beats (L26: 3×3, 512 input channels) |
| Line buffer | 8 × 1024 × 128 b = 128 KB | 3×3 stride 2 needs 3 rows plus prefetch; widest row is 1024 beats |
| Output FIFO | 16 pixels | credit-based, so the compute pipeline never stalls |
| Epilogue | 32 × DSP48 | 27 × 18 multiply per channel |

**Why the pipeline never stalls:** the only decision point is the issue stage. A pixel starts only if
(a) all its input rows are already in the line buffer, and (b) a slot in the output FIFO is reserved
for it. Everything after that is a fixed-latency pipeline, so there are no back-pressure paths in the datapath.

## 6. Numerics
```
x_q  = pixel >> 1                         (scale 2/255)
acc  = Σ w_q · x_q                        (int32)
t    = sat27(acc + bias)                  (27-bit, fits the DSP A port)
y    = clamp8((t · (t<0 ? Mneg : Mpos) + 2^(sh−1)) >>> sh)
```
`Mneg = round(0.1·Mpos)` implements leaky ReLU exactly inside the requantisation. Head outputs are
INT8 with scales 0.2058 (13×13) and 0.1985 (26×26). The CPU dequantises only the channels it needs for decode.

## 7. Performance breakdown (RTL simulation, 7.48 M cycles = 39.9 ms at 187.5 MHz)

| Component | Cycles | Share |
|---|---|---|
| Useful MAC cycles (512 MAC/cycle) | 6.97 M | 93 % |
| Weight loading (not overlapped) | 0.38 M | 5 % |
| Waiting for input rows (layer/group starts) | 0.14 M | 2 % |
| Waiting for output credits | 0 | 0 % |

The five biggest layers are L35, L26, L18, L10 and L2, at 0.8–1.2 M cycles each. DDR traffic is about
44 MiB per frame, about 1.1 GB/s at 25 fps, far below HP0's capability.

**Upgrade paths**, if more speed is needed:
* Double-buffer the weight banks: −5 %.
* Pack 2 INT8 MACs per DSP48 and double the array to 1,024 MACs: about 45–50 fps. 1,690 DSPs are free.
* Run the PL at 250 MHz with an MMCM once memory allows the IP to be created.

## 8. Verification strategy
```
darknet ──(same detections)── float model ──(mAP −0.16)── INT8 tensor model
                                                             ║ bit-exact (check_hwsim.py)
                                                     descriptor-level DDR simulator
                                                             ║ bit-exact, whole DDR image
                                                  RTL (xsim): feature test + full network
                                                             ║ bit-exact
                                                  gate-level netlist (feature test)
                                                             ║ (next)
                                                  board: yolo_server --selftest
```
