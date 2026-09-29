# scripts — project helper scripts

| Script | What it does |
|---|---|
| `copy_from_E.bat` | One-time import from the original workspace `E:\yolo_mpsoc` (never modified) using `robocopy`: cfg and `obj.data` → `00_model/cfg`, all `.weights` → `00_model/weights`, darknet predictions → `00_model/darknet_predictions`, dataset and its scripts → `01_dataset`, `darknet\build\Release` → `tools/darknet_win`, `bad.list` → `logs/darknet_bad.list`. Log: `logs/copy.log`; writes `logs/copy.done` when finished. Safe to re-run: robocopy only copies missing or changed files. |

The build and simulation scripts live next to what they build:
* `05_tb/run_xsim.bat`
* `05_tb/gatesim/run_gatesim.bat`
* `06_vivado/build.bat`
* `07_sw/board/build_board.bat`
