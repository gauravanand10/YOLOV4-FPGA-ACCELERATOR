@echo off
REM Full ZCU104 build: project + block design + synth + impl + bitstream + .xsa
REM   build.bat          full build (stage 1 "prep": project + BD + wrapper, stage 2 "runs": synth/impl/bit/xsa)
REM   build.bat bdonly   only create + validate the block design (quick check)
REM   build.bat runs     stage 2 only: reuse the prepared project (and a completed synth_1), redo impl
REM Logs: D:\MPSOC_YOLO\logs\vivado_prep.log (stage 1 / bdonly), vivado_build.log (stage 2)
REM Reports: 06_vivado\reports   Outputs: 06_vivado\out
REM The two stages run in separate Vivado processes so the ~3 GB BD session is not resident during
REM synthesis/implementation (16 GB PC). Needs about 5-6 GB of free memory.
REM On this PC the antivirus (McAfee + Defender real-time) sometimes makes Vivado fail to open its own
REM Tcl files ("couldn't read file ... no such file or directory"). Such runs are retried up to 3 times;
REM the permanent fix is to exclude C:\Xilinx and D:\MPSOC_YOLO from real-time scanning.
setlocal
set VIV=C:\Xilinx\Vivado\2024.1\bin
set LOGD=D:\MPSOC_YOLO\logs
cd /d %~dp0
if exist out\yolo_zcu104.bit del /q out\yolo_zcu104.bit
if exist out\yolo_zcu104.xsa del /q out\yolo_zcu104.xsa

if /I "%~1"=="bdonly" (
  call :stage vivado_prep bdonly clean || exit /b 1
  findstr /C:"BDONLY DONE" %LOGD%\vivado_prep.log >nul || (echo VIVADO BD CHECK FAILED - see %LOGD%\vivado_prep.log & exit /b 1)
  echo VIVADO BD CHECK OK
  type reports\clock.txt
  exit /b 0
)
if /I "%~1"=="runs" goto runs
call :stage vivado_prep prep clean || exit /b 1
findstr /C:"PREP DONE" %LOGD%\vivado_prep.log >nul || (echo VIVADO PREP FAILED - see %LOGD%\vivado_prep.log & exit /b 1)
:runs
call :stage vivado_build runs keep || exit /b 1
REM Vivado can crash with exit code 0, so also require the final marker and the outputs
findstr /C:"BUILD DONE" %LOGD%\vivado_build.log >nul || (echo VIVADO BUILD FAILED - no BUILD DONE marker, see %LOGD%\vivado_build.log & exit /b 1)
if not exist out\yolo_zcu104.bit (echo VIVADO BUILD FAILED - out\yolo_zcu104.bit missing & exit /b 1)
if not exist out\yolo_zcu104.xsa (echo VIVADO BUILD FAILED - out\yolo_zcu104.xsa missing & exit /b 1)
echo VIVADO BUILD OK
type reports\summary.txt
exit /b 0

REM ---- :stage <logname> <tclarg> <clean|keep> : run one Vivado batch, retry transient file-read errors ----
:stage
set LOG=%LOGD%\%~1.log
set TRY=0
:attempt
set /a TRY+=1
if "%~3"=="clean" (
  if exist proj rmdir /s /q proj
  if exist .Xil rmdir /s /q .Xil
)
echo [build.bat] %~2 attempt %TRY%
call %VIV%\vivado.bat -mode batch -notrace -source build.tcl -log %LOG% -journal %LOGD%\%~1.jou -tclargs %~2
set RC=%ERRORLEVEL%
set FLAKY=0
findstr /C:"couldn't read file" %LOG% >nul && set FLAKY=1
if not "%RC%"=="0" if exist proj\yolo_zcu104.runs findstr /S /M /C:"couldn't read file" proj\yolo_zcu104.runs\runme.log >nul 2>&1 && set FLAKY=1
if "%FLAKY%"=="1" if %TRY% LSS 3 (
  copy /y %LOG% %LOGD%\%~1_fileread_fail_%TRY%.log >nul
  echo [build.bat] transient "couldn't read file" error, retrying
  goto attempt
)
if not "%RC%"=="0" (echo VIVADO %~2 FAILED - exit code %RC%, see %LOG% & exit /b 1)
findstr /R /C:"^ERROR:" %LOG% >nul && (echo VIVADO %~2 FAILED - errors in %LOG% & exit /b 1)
exit /b 0
