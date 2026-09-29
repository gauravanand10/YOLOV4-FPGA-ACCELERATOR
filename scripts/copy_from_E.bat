@echo off
REM Copies the trained YOLOv4-tiny 7-class assets from E:\yolo_mpsoc into this tree
set SRC=E:\yolo_mpsoc
set DST=D:\MPSOC_YOLO
set LOG=%DST%\logs\copy.log
echo START %DATE% %TIME% > "%LOG%"
robocopy "%SRC%\models"  "%DST%\00_model\cfg" *.cfg obj.data /NP /R:1 /W:1 >> "%LOG%"
robocopy "%SRC%\weights" "%DST%\00_model\weights" /E /NP /R:1 /W:1 >> "%LOG%"
robocopy "%SRC%\YOLO_predictions_10" "%DST%\00_model\darknet_predictions" /E /NP /R:1 /W:1 >> "%LOG%"
copy /Y "%SRC%\predictions.jpg" "%DST%\00_model\darknet_predictions\" >> "%LOG%"
robocopy "%SRC%\scripts" "%DST%\01_dataset\scripts" /E /NP /R:1 /W:1 >> "%LOG%"
robocopy "%SRC%\dataset" "%DST%\01_dataset" /E /NP /NFL /NDL /R:1 /W:1 /MT:16 >> "%LOG%"
robocopy "%SRC%\darknet\build\Release" "%DST%\tools\darknet_win" /E /NP /R:1 /W:1 >> "%LOG%"
copy /Y "%SRC%\bad.list" "%DST%\logs\darknet_bad.list" >> "%LOG%"
echo DONE %DATE% %TIME% >> "%LOG%"
echo COPY_FINISHED > "%DST%\logs\copy.done"
