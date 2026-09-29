# 06_vivado — ZCU104 hardware build (block design → bitstream → .xsa)

Fully scripted: nothing in the Vivado GUI is needed. Tool: **Vivado 2024.1** at `C:\Xilinx`.
Part `xczu7ev-ffvc1156-2-e`, board part `xilinx.com:zcu104:part0:1.1`.

## Files

| File | Role |
|---|---|
| `build.bat` | Entry point. Runs the Tcl in two separate Vivado processes, retries antivirus-caused file-read failures up to 3×, and only prints OK if Vivado exited 0, the log has no `ERROR:`, the `BUILD DONE` marker is present and the `.bit`/`.xsa` exist. |
| `build.tcl` | Creates the project and block design, validates, generates, synthesises, implements, writes the bitstream, exports the `.xsa` and all reports. Aborts if WNS or WHS < 0. |
| `lowmem_pre.tcl` | Synthesis pre-hook: 1 thread, no helper processes (otherwise 4 × ~2 GB). |
| `lowmem_impl_pre.tcl` | Implementation pre-hook: 2 threads for place and route. |
| `out/` | **Deliverables** (below) |
| `reports/` | Utilization, timing, power, DRC, clock |
| `proj/` | Vivado project (generated; can be deleted and rebuilt) |

## Usage
```bat
build.bat            & rem full build, about 45 min, needs about 5-6 GB of free RAM
build.bat bdonly     & rem 2 min: create and validate the block design only
build.bat runs       & rem reuse the prepared project and any finished synth/impl, redo only what is missing
```
Logs: `D:\MPSOC_YOLO\logs\vivado_prep.log` (stage 1), `vivado_build.log` (stage 2), `vivado_build_console.log`.
Close VS Code, browsers and Docker first; `wsl --shutdown` frees the WSL VM.

## Block design (`system`)

```
 ┌──────────────────── zynq_ps (Zynq US+ MPSoC, ZCU104 preset) ─────────────────────┐
 │  M_AXI_HPM0_FPD      S_AXI_HP0_FPD      pl_clk0        pl_resetn0     pl_ps_irq0 │
 └───────┬──────────────────▲─────────────────┬──────────────┬────────────────▲────┘
         │ 32b              │ 128b            │ 187.5 MHz    │                │
    ┌────▼────┐        ┌────┴────┐            │ (every aclk) ┌▼─────────┐     │
    │ sc_ctrl │        │ sc_mem  │            │              │ rst_pl0  │     │
    └────┬────┘        └────▲────┘            │              └┬─────────┘     │
         │ s_axi (AXI-Lite) │ m_axi (AXI4)    │               │ aresetn       │ irq
    ┌────▼──────────────────┴─────────────────▼───────────────▼───────────────┴────┐
    │                 yolo_accel   (module reference: yolo_accel_wrap)             │
    └──────────────────────────────────────────────────────────────────────────────┘
```

| Item | Setting |
|---|---|
| Clock | Everything runs on **pl_clk0 = 187.5 MHz** (IOPLL 1500 / 8). The script requests 200 MHz, reads back `PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ`, and falls back to 187.5 MHz because 200 is not exact. No MMCM/clk_wiz: creating one crashed Vivado on this 16 GB PC. |
| FREQ_HZ | Copied from pl_clk0 onto `yolo_accel/aclk`, `s_axi` and `m_axi`, so `validate_bd_design` has no mismatch |
| Control | M_AXI_HPM0_FPD (32-bit) → sc_ctrl → accelerator registers at **0xA000_0000, 4 KiB** |
| Data | Accelerator m_axi (128-bit) → sc_mem → **S_AXI_HP0_FPD** (128-bit). Only DDR_LOW (0–2 GiB) is mapped; OCM and QSPI are excluded. |
| AxUSER | The wrapper drives 1-bit `awuser/aruser = 0` to match HP0 (removes the width warning) |
| Interrupt | `irq` → `pl_ps_irq0` (the board app polls; the IRQ is optional) |
| Reset | `proc_sys_reset` from `pl_resetn0` |
| Synthesis | BD synthesised globally (`synth_checkpoint_mode None`); post-route phys_opt enabled |

## Outputs (`out/`)

| File | Size | Used for |
|---|---|---|
| `yolo_zcu104.bit` | 19.3 MB | JTAG programming, or BOOT.BIN via `petalinux-package --fpga` |
| `yolo_zcu104.bit.bin` | 19.3 MB | Runtime loading on Linux with `fpgautil -b` (made with `bootgen -arch zynqmp -process_bitstream bin`, `bit2bin.bif`) |
| `yolo_zcu104.xsa` | 2.95 MB | Hardware platform for PetaLinux/Vitis (`write_hw_platform -fixed -include_bit`) |

## Results (post-route) — `reports/`

| Metric | Value |
|---|---|
| Clock | 187.5 MHz (5.333 ns) |
| Setup WNS / TNS | **+0.099 ns** / 0.000 (0 failing of 56,989 endpoints) |
| Hold WHS / THS | **+0.010 ns** / 0.000 |
| Pulse width WPWS | +1.166 ns |
| CLB LUTs | 56,696 / 230,400 (24.6 %); accelerator alone 54,653 |
| CLB registers | 23,610 / 460,800 (5.1 %) |
| Block RAM | 96.5 / 312 tiles (30.9 %): 64 weight banks, about 29 line buffer, the rest pool row |
| URAM | 0 / 96 |
| DSP48E2 | 37 / 1,728 (2.1 %): 32 epilogue, 2 line loader, 2 writer, 1 engine |
| Power | 4.91 W total: PS 2.64 W, PL dynamic about 1.57 W, static 0.70 W, Tj 29.8 °C |
| DRC | 73 warnings (DSP pipelining advice DPIP/DPOP/DPREG, 1 RTSTAT-10), **0 errors** |

| Report | Content |
|---|---|
| `summary.txt` | PL0 MHz, WNS, WHS (machine-readable) |
| `clock.txt` | actual pl_clk0 frequency and FREQ_HZ |
| `timing_impl.rpt` / `timing_synth.rpt` | timing summary, top 20 paths |
| `utilization_impl.rpt`, `utilization_hier.rpt`, `utilization_core_hier.rpt`, `utilization_synth.rpt` | flat and hierarchical usage |
| `power.rpt`, `drc.rpt` | power estimate, DRC |

## Lessons from the build (on a 16 GB Windows PC)
* Peak memory is about 4.8 GB in synthesis and 4–5 GB in implementation, with the settings above.
* McAfee/Defender real-time scanning can make Vivado fail to read its own Tcl files. Exclude
  `C:\Xilinx` and `D:\MPSOC_YOLO` from scanning (admin rights needed); `build.bat` retries meanwhile.
* Synthesis rejected a string parameter inside `(* ram_style = ... *)` in `sdp_ram.sv` (Synth 8-281);
  it is now the literal `"block"`.
* Timing margin is small. The first places to add a register are the PE adder tree, the epilogue
  multiply/round, and the line-buffer read path. Re-run the `05_tb` regressions after any such change.
