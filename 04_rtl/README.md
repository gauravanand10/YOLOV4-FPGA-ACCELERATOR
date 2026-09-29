# 04_rtl — the YOLOv4-tiny INT8 accelerator (synthesizable SystemVerilog)

13 files, about 1,270 lines. They are lint-clean in Verilator (`-Wall`), xvlog/xelab and Vivado
synthesis. The top for the block design is `yolo_accel_wrap.v`, a plain Verilog-2001 wrapper around
`yolo_accel.sv`, because IP integrator module references cannot use SV struct ports.

## Block diagram

```
              AXI-Lite (32b, HPM0_FPD @ 0xA000_0000)
                   │
            ┌──────▼──────┐  start / desc_addr / num_layers        irq ─► pl_ps_irq0
            │  axil_regs  │◄─ busy, done, cycles, cur_layer, stall counters
            └──────┬──────┘
                   │
┌──────────────────▼───────────────────────────────── yolo_accel ─────────────────────────────┐
│  control FSM: DESC_AR → DESC_R → DECODE → { WL_START → WL_WAIT → ST_START → ST_WAIT }×ngrp   │
│               → LAYER_END (wait all B) → next layer … → DONE                                 │
│                                                                                              │
│   AXI read mux (rsel: 0 = descriptor, 1 = weights, 2 = lines) ◄──── m_axi AR/R (128b) ◄── DDR │
│        │                       │                                                             │
│  ┌─────▼────────┐       ┌──────▼───────┐                                                     │
│  │weight_loader │       │ line_loader  │  2×2 maxpool on the fly (pool=1)                    │
│  │ + burst_gen  │       │ + burst_gen  │  row r allowed only if r < row_limit                │
│  └──┬───────┬───┘       └──────┬───────┘                                                     │
│     │params │weights           │ rows (slot = r mod 8)                                       │
│  ┌──▼───────▼──────────────────▼────────────────────────── conv_engine ─────────────┐        │
│  │ prm[32]   weight banks 32×(512×128b)   line buffer 8×1024×128b                   │        │
│  │ issue (oy,ox,ky,kx,c) → addr → BRAM rd (2) → pe_array 32×16 (3) → accumulate     │        │
│  │ → epilogue ×32 lanes (5) → output FIFO (16 pixels × 256b, credit based)          │        │
│  └───────────────────────────────────────────────────────────────┬─────────────────┘        │
│                                                                  │ 32-channel pixels         │
│                                                          ┌───────▼──────┐                    │
│                                                          │    writer    │ 2×2 upsample, 2nd dest │
│                                                          └───────┬──────┘                    │
└──────────────────────────────────────────────────────────────────┼──────────────────────────┘
                                                                   ▼ m_axi AW/W/B (32-B bursts) ─► DDR
```

## Files

| File | Module | What it does |
|---|---|---|
| `yolo_pkg.sv` | package | Constants (`NOC=32`, `NIC=16`, 8-slot×1024 line buffer, 512-deep weight banks, 16-pixel output FIFO, `ACCEL_ID = 0x594F4C34` "YOL4"), the `desc_t` descriptor struct with `unpack_desc()`, and `vmax8()` (16-lane signed byte max for pooling). |
| `yolo_accel_wrap.v` | `yolo_accel_wrap` | Verilog-2001 wrapper used by the Vivado block design. `aclk`/`aresetn` carry no fixed `FREQ_HZ`; Vivado copies it from pl_clk0. Adds 1-bit `m_axi_awuser/aruser` tied to 0 to match HP0. |
| `yolo_accel.sv` | `yolo_accel` | Top: register block, control FSM, descriptor fetch (4 beats = 64 B at `DESC_ADDR + 64·layer`), AXI read mux between descriptor/weights/lines, sub-module wiring, fixed AXI attributes (INCR, 16-byte beats, cache 0011, all strobes). At layer end it waits for every write response so the next layer never reads stale data. |
| `axil_regs.sv` | `axil_regs` | AXI4-Lite slave. AW and W are accepted independently. Register map below. |
| `burst_gen.sv` | `burst_gen` | Splits a contiguous read (address, beats) into AXI bursts of ≤ 64 beats that never cross a 4 KiB boundary. |
| `weight_loader.sv` | `weight_loader` | For one 32-channel group, reads 32 parameter beats (to `prm[o]`) then 32·kkcc weight beats. Beat n of output channel o is written to bank o at address n (= tap·cc + c). |
| `line_loader.sv` | `line_loader` | Streams conv input rows 0…in_hc-1 into line-buffer slot `r mod 8` at address `x·cc + c`. It reads full pixels (`in_ps` stride) and keeps only the chunks the layer needs. With `pool = 1`, each conv row is the 2×2/s2 max of stored rows 2r and 2r+1: horizontal max in `hreg[c]`, vertical max via a pool row buffer. Only fetches row r when r < `row_limit` from the engine. |
| `conv_engine.sv` | `conv_engine` | Computes one 32-output-channel group (next section). |
| `pe_array.sv` | `pe_array` | 32 lanes × 16 INT8 multipliers. Each lane is a 16-input dot product through a pipelined adder tree: product reg (16 b) → 16→4 (18 b) → 4→1 (20 b). Latency 3. |
| `epilogue.sv` | `epilogue` | 32 lanes in parallel, 5 stages: bias add + saturate to 27 b and pick Mpos/Mneg → 27×18 multiply (DSP48) → add rounding constant → arithmetic shift → clamp to int8. |
| `writer.sv` | `writer` | Pops 32-channel pixels and writes each as one 32-byte burst (2 beats) to `addr0 + pixel·ps0 + grp·32`. Optionally writes the same pixel to a second destination (`en1`), and with `ups = 1` writes it to a 2×2 block. Addresses are incremental (no per-pixel multiplier). Counts outstanding B responses. |
| `sdp_ram.sv` | `sdp_ram` | Simple dual-port RAM, `ram_style = "block"`, read latency 1 or 2 (DOB_REG). |
| `sync_fifo.sv` | `sync_fifo` | First-word-fall-through FIFO (output pixel FIFO). |

## conv_engine in detail

**Loop order.** For each output pixel (oy, ox), the loop runs over ky, kx and input chunk c, one step per
cycle. So a pixel takes `kkcc = k·k·⌈cin/16⌉` cycles, and each cycle does 32 × 16 = **512 MACs**.

| Stage | Cycle | Work |
|---|---|---|
| S0 issue | 0 | counters, `iy = oy·s − pad + ky`, `ix = ox·s − pad + kx`, weight address `wa` |
| S1 address | 1 | line-buffer address `{iy[2:0], ix·cc + c}`, in-bounds flag (padding → zeros) |
| BRAM read | 2–3 | line buffer (1 × 128 b) and 32 weight banks (32 × 128 b) in parallel |
| PE array | 4–6 | 512 products, 32 dot products |
| Accumulate | 7 | `acc[o] += psum[o]` (reset on first tap, output on last tap) |
| Epilogue | 8–12 | requantise 32 channels |
| Output FIFO | 13 | 256-bit pixel to the writer |

**Flow control, without stalling the pipeline.** A new pixel is issued only when both hold:
* its input rows are already in the line buffer (`rows_done ≥ min(row_min + k, in_hc)`);
* an output-FIFO credit is free (fewer than 16 pixels between issue and writer pop).

Because of these checks, nothing behind S0 ever has to stall.

**Line-buffer reuse.** The loader may overwrite slot `r mod 8` once `r < row_min + 8`. That limit is
delayed 4 cycles so reads still in flight to the old row finish first.

## Register map (AXI-Lite, base 0xA000_0000, 4 KiB)

| Offset | Name | Access | Meaning |
|---|---|---|---|
| 0x00 | CTRL | W / RW | [0] start (self-clearing), [1] irq_en |
| 0x04 | STATUS | R / W1C | [0] busy, [1] done (write 1 to clear; also clears IRQ) |
| 0x08 | DESC_ADDR | RW | physical address of the descriptor table |
| 0x0C | NUM_LAYERS | RW | number of descriptors to run (21 for YOLOv4-tiny) |
| 0x10 | CYCLES | R | clock cycles of the current/last run |
| 0x14 | CUR_LAYER | R | layer being executed |
| 0x18 | ID | R | 0x594F4C34 ("YOL4"), for a bring-up check |
| 0x1C | STALL_ROW | R | cycles the engine waited for input rows |
| 0x20 | STALL_OUT | R | cycles the engine waited for output credits |
| 0x24 | WLOAD_CYC | R | cycles spent loading weights |

**Run sequence:** write DESC_ADDR and NUM_LAYERS → write CTRL = 1 (or 3 with IRQ) → poll STATUS[1] →
write STATUS = 2 → read CYCLES.

## AXI master behaviour
* 128-bit data, 32-bit address, ID 0, INCR bursts of ≤ 64 beats that never cross 4 KiB. `rready` is
  always 1: every read client accepts one beat per cycle.
* Reads: descriptor (4 beats), weights (32 + 32·kkcc beats per group), input rows (in_w · in_ps / 16 beats per row).
* Writes: 2-beat bursts per output pixel (×4 with upsample, ×2 with a second destination). All B
  responses are awaited at layer end.

## Implemented results (Vivado 2024.1, ZCU104, 187.5 MHz)

| Block | LUT | FF | RAMB36 | DSP |
|---|---|---|---|---|
| pe_array | 26,176 | 11,136 | 0 | 0 |
| epilogue | 9,058 | 3,169 | 0 | 32 |
| weight banks (32) | 32 × 560 | 0 | 64 | 0 |
| line buffer | 5,496 | 0 | 28 (+1 RAMB18) | 0 |
| **whole accelerator** | **54,653** | **21,279** | **96 (+1)** | **37** |

* The 512 INT8 multipliers are mapped to LUTs. 11,136 FFs = 512 × 16 (products) + 128 × 18 + 32 × 20
  (adder-tree stages), which proves the array is complete.
* The LUTs credited to the weight banks and line buffer are multiplier logic that synthesis moved
  across hierarchy boundaries.
* Timing: WNS +0.099 ns at 5.333 ns. If a change breaks timing, pipeline the adder tree or the epilogue first.

## Conventions
* Synchronous active-low reset (`rst_n`, from `aresetn`). A single clock domain.
* `` `ifndef SYNTHESIS `` guarded `$error` checks (for example output-FIFO overflow) exist only in simulation.
* Any RTL change must be followed by `05_tb\run_xsim.bat feature 30 3 2` (fast) and, before a new
  bitstream, `run_xsim.bat yolo 0 40 1` (full network).
