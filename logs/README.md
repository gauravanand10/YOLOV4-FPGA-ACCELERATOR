# logs — tool output (evidence for every result in the READMEs)

| Log | Produced by | Key line |
|---|---|---|
| `copy.log`, `copy.done` | `scripts/copy_from_E.bat` | copy of `E:\yolo_mpsoc` finished |
| `map_eval.log` | `02_golden_model/eval_map.py 500` | mAP float 41.19 / INT8 41.03 |
| `xvlog.log`, `xelab.log` | `05_tb/run_xsim.bat` (compile) | 0 errors |
| `xsim_feature.log` (+ `*_backup` runs) | `run_xsim.bat feature …` | `TEST PASSED: … 28928 words bit-exact` |
| `xsim_feature_neg.log` | feature test with a corrupted expectation | mismatch detected (the checker works) |
| `xsim_yolo.log`, `xsim_yolo_console.log` | `run_xsim.bat yolo 0 40 1` | `TEST PASSED: … 948224 words bit-exact`, 7,481,892 cycles |
| `gatesim_*.log` | `05_tb/gatesim/run_gatesim.bat` | gate-level `TEST PASSED`, 56,405 cycles |
| `netlist_check.log` | `05_tb/gatesim/netlist_check.tcl` | hierarchy and cell counts of the OOC netlist |
| `vivado_prep.log` | `06_vivado/build.bat` stage 1 | `PREP DONE`, BD validated, pl_clk0 187.5 MHz |
| `vivado_build.log`, `vivado_build_console.log` | `06_vivado/build.bat` stage 2 | `BUILD DONE`, WNS +0.099 / WHS +0.010 |
| `vivado_*_NNNN.backup.*`, `vivado_prep_fileread_fail_1.log` | earlier / failed attempts (clock mismatch, antivirus file-read failures) | history only |
| `sim_server.log` | `07_sw/host/sim_server.py` | the earlier out-of-memory error (since fixed) |
| `darknet_bad.list` | darknet training (copied from `E:`) | ~2.7k training images whose labels were not found |
| `old/` | logs from before the clean rebuild | history only |

Vivado writes a `*.backup.*` copy of the previous log every time it starts; those can be deleted.
