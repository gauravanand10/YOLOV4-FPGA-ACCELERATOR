# tools — third-party binaries

## darknet_win/
The Windows build of AlexeyAB darknet used to train the model and make `00_model/darknet_predictions`.
It was copied from `E:\yolo_mpsoc\darknet\build\Release`.

| File | |
|---|---|
| `darknet.exe`, `darknet.dll`, `darknet.lib/.exp` | darknet (built with vcpkg: OpenCV, optionally CUDA) |
| `pthreadVC2.dll` | pthreads for Windows |
| `kmeansiou.exe` | anchor clustering tool |
| `uselib.exe` | library demo |

**It does not run from this folder on its own.** It needs the OpenCV DLLs (`opencv_core4.dll`, …; plus CUDA DLLs if it was built with CUDA) that live in `E:\yolo_mpsoc\vcpkg\installed\x64-windows\bin` (see
`02_golden_model/darknet_check/out.txt`). Run it from the original `E:\yolo_mpsoc` tree, or add that
`bin` folder to `PATH`. The hardware flow does not need darknet; the Python golden model replaces it.
