$darknet = "E:\yolo_mpsoc\darknet\build\Release\darknet.exe"
$data    = "E:\yolo_mpsoc\models\obj.data"
$cfg     = "E:\yolo_mpsoc\models\yolov4-tiny-7class-train.cfg"
$weights = "E:\yolo_mpsoc\weights\yolov4-tiny-7class-train_final.weights"

$source = "E:\yolo_mpsoc\dataset\images\valid"
$dest   = "$env:USERPROFILE\Desktop\YOLO_predictions_10"

New-Item -ItemType Directory -Force -Path $dest | Out-Null

$images = Get-ChildItem $source -Filter *.jpg | Select-Object -First 10

$i = 1

foreach ($img in $images) {

    Write-Host ""
    Write-Host "======================================"
    Write-Host "Processing $i / 10 : $($img.Name)"
    Write-Host "======================================"

    & $darknet detector test `
        $data `
        $cfg `
        $weights `
        $img.FullName `
        -thresh 0.25 `
        -dont_show

    if (Test-Path "E:\yolo_mpsoc\predictions.jpg") {

        Copy-Item `
            "E:\yolo_mpsoc\predictions.jpg" `
            "$dest\prediction_$('{0:D2}' -f $i).jpg" `
            -Force

        Write-Host "Saved prediction_$('{0:D2}' -f $i).jpg" -ForegroundColor Green
    }
    else {
        Write-Host "ERROR: predictions.jpg not found" -ForegroundColor Red
    }

    $i++
}

Write-Host ""
Write-Host "======================================"
Write-Host "DONE"
Write-Host "======================================"
Write-Host "Saved to:"
Write-Host $dest