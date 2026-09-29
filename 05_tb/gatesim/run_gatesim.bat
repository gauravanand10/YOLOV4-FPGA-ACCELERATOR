@echo off
REM Gate-level (post-synthesis functional) simulation of the accelerator with the 05_tb testbench.
REM   run_gatesim.bat [test=feature] [stall_pct=0] [rd_latency=40] [runs=1] [nosynth]
REM 1) ooc_synth.tcl: out-of-context synth of yolo_accel_wrap -> yolo_accel_wrap_funcsim.v (skip with nosynth)
REM 2) make_tb_gate.py: tb_top_gate.sv (tb copy without dut.u_core peeks, waits for glbl GSR)
REM 3) xvlog/xelab (UNISIM) + xsim; log -> D:\MPSOC_YOLO\logs\gatesim_<test>.log
setlocal
set VIV=C:\Xilinx\Vivado\2024.1\bin
set TEST=%~1
if "%TEST%"=="" set TEST=feature
set STALL=%~2
if "%STALL%"=="" set STALL=0
set LAT=%~3
if "%LAT%"=="" set LAT=40
set RUNS=%~4
if "%RUNS%"=="" set RUNS=1
cd /d %~dp0
if /I not "%~5"=="nosynth" (
  call %VIV%\vivado.bat -mode batch -notrace -source ooc_synth.tcl -log ..\..\logs\gatesim_ooc_synth.log -journal ..\..\logs\gatesim_ooc_synth.jou || exit /b 1
)
python make_tb_gate.py || exit /b 1
if not exist sim mkdir sim
cd sim
call %VIV%\xvlog.bat -sv -f ..\files_gate.f --log ..\..\..\logs\gatesim_xvlog.log || exit /b 1
call %VIV%\xelab.bat tb_top glbl -L unisims_ver -s tb_gate -timescale 1ns/1ps -debug off --log ..\..\..\logs\gatesim_xelab.log || exit /b 1
call %VIV%\xsim.bat tb_gate -R -testplusarg "DATA=../../data/%TEST%" -testplusarg "STALL=%STALL%" -testplusarg "LAT=%LAT%" -testplusarg "RUNS=%RUNS%" -log ..\..\..\logs\gatesim_%TEST%.log
findstr /C:"TEST PASSED" ..\..\..\logs\gatesim_%TEST%.log >nul && (echo GATESIM PASS %TEST%) || (echo GATESIM FAIL %TEST% & exit /b 1)
