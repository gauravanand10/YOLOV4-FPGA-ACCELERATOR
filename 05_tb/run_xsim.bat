@echo off
REM usage: run_xsim.bat [test=feature|yolo] [stall_pct=0] [rd_latency=40] [runs=1] [nocompile]
REM compiles RTL + TB with Vivado xsim and runs the bit-exact test; log -> D:\MPSOC_YOLO\logs\xsim_<test>.log
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
if not exist sim mkdir sim
cd sim
if "%~5"=="nocompile" goto run
call %VIV%\xvlog.bat -sv -f ..\files_sim.f --log ..\..\logs\xvlog.log || exit /b 1
call %VIV%\xelab.bat tb_top -s tb_snap -timescale 1ns/1ps -O3 -debug off --log ..\..\logs\xelab.log || exit /b 1
:run
call %VIV%\xsim.bat tb_snap -R -testplusarg "DATA=../data/%TEST%" -testplusarg "STALL=%STALL%" -testplusarg "LAT=%LAT%" -testplusarg "RUNS=%RUNS%" -log ..\..\logs\xsim_%TEST%.log
findstr /C:"TEST PASSED" ..\..\logs\xsim_%TEST%.log >nul && (echo PASS %TEST%) || (echo FAIL %TEST% & exit /b 1)
