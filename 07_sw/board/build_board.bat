@echo off
REM Cross-compile the board application with the aarch64 Linux toolchain shipped with Vitis 2024.1
REM output: 07_sw\board\deploy\ (copy to the board, e.g. scp -r deploy root@<board-ip>:/home/root/yolo)
setlocal
set TC=C:\Xilinx\Vitis\2024.1\gnu\aarch64\nt\aarch64-linux\bin
cd /d %~dp0
copy /y ..\..\03_quant_export\out\model_params.h . >nul
if not exist deploy mkdir deploy
%TC%\aarch64-linux-gnu-gcc.exe -O3 -Wall -Wextra -mcpu=cortex-a53 -o deploy\yolo_server yolo_server.c yolo_accel.c yolo_post.c -lpthread -lm || exit /b 1
for %%f in (yolo_desc.bin yolo_weights.bin test_input_rgb.bin test_heads.bin test_dets.txt) do copy /y ..\..\03_quant_export\out\%%f deploy\ >nul
echo board app built: %~dp0deploy
