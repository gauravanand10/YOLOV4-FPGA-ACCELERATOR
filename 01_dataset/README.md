# 01_dataset — COCO-2017, 7-class subset

Copied from `E:\yolo_mpsoc\dataset`. The training was done on this data. The hardware flow uses the
validation images only: 100 for INT8 calibration and 500 for mAP.

## Classes (`classes.names`)
`0 person · 1 car · 2 bicycle · 3 bottle · 4 chair · 5 laptop · 6 cup`

## Contents
| Path | What it is |
|---|---|
| `train.txt`, `valid.txt` | darknet image lists, 8,000 and 2,000 lines (paths still point to `E:/yolo_mpsoc/...`) |
| `selected_train_ids.txt`, `selected_valid_ids.txt` | COCO image IDs of the balanced subset (seed 42) |
| `coco_7class_image_ids.txt` | every COCO train2017 image that contains at least one of the 7 classes |
| `images/train`, `images/valid` | JPEG images (plus a copy of the label `.txt` next to each image) |
| `labels/train`, `labels/valid` | YOLO labels: `cls cx cy w h`, normalised |
| `downloads/annotations/` + `annotations_trainval2017.zip` | original COCO 2017 annotation JSONs (~1.1 GB) |
| `train/`, `valid/` | empty (left over from the original layout) |
| `scripts/` | the pipeline that built this dataset (below) |

## scripts/
| Script | Step |
|---|---|
| `prepare_coco_7class.py` | prints the class list (placeholder first step) |
| `select_coco_7class.py` | finds all COCO images containing the 7 classes → `coco_7class_image_ids.txt` |
| `select_balanced_coco.py` | greedy class-balanced pick of 8,000 train and 2,000 valid images (seed 42) |
| `download_convert_coco.py` | downloads the images, converts COCO boxes to YOLO labels, writes `train.txt`/`valid.txt` |
| `save_10_predictions.ps1` | runs `darknet.exe detector test` on 10 valid images → `00_model/darknet_predictions` |

## Known issues (check before retraining)
1. **About 2,700 unlabeled training images.** `logs/darknet_bad.list` lists training images whose
   labels darknet could not open. It searched `images/train/*.txt` while labels were in `labels/train/`,
   so those images were trained as pure background. This probably costs mAP.
2. **Only 3,721 training JPEGs on D:.** `images/train` here holds 3,721 JPEGs, but `labels/train` and
   `train.txt` list 8,000. `images/valid` is complete (2,000). Compare with
   `E:\yolo_mpsoc\dataset\images\train`: if E: has more, re-run `scripts\copy_from_E.bat`; if not,
   re-download with `download_convert_coco.py`. The hardware flow is **not** affected, since it only
   uses validation images.
3. Paths in `train.txt`, `valid.txt` and `00_model/cfg/obj.data` still use `E:/`. Rewrite them to
   `D:/MPSOC_YOLO/01_dataset/...` before training from this copy.
