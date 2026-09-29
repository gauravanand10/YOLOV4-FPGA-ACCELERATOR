# 00_model — trained network (source of truth for everything downstream)

Copied unchanged from `E:\yolo_mpsoc` by `scripts/copy_from_E.bat`.

## cfg/
| File | What it is | Use it? |
|---|---|---|
| `yolov4-tiny-7class-train.cfg` | The config the model was trained with (7 classes, 36-filter heads, max_batches 14000) | **Yes. Every tool in this project uses it.** |
| `yolov4-tiny-7class.cfg` | Same network, but with darknet's default long training schedule | No (reference only) |
| `yolov4_tiny_7class.cfg` | Despite the name, this is the stock **80-class** COCO cfg (255 filters, `mask=1,2,3`) | **No** |
| `obj.data` | darknet data file (`classes=7`, train/valid lists, names, backup) | Still points to `E:/yolo_mpsoc/...`; see `02_golden_model/darknet_check/obj_local.data` for a D: version |

## weights/
| File | Size | What it is |
|---|---|---|
| `yolov4-tiny-7class-train_final.weights` | 23.6 MB | **Final trained model.** Used by the golden model, the export and the hardware. |
| `yolov4-tiny-7class-train_last.weights` | 23.6 MB | Last checkpoint, saved at the same time as `_final` |
| `yolov4-tiny-7class-train_10000.weights` | 23.6 MB | Checkpoint at iteration 10,000 |
| `yolov4-tiny.conv.29` | 19.8 MB | ImageNet/COCO pretrained backbone the training started from |

## darknet_predictions/
`prediction_01..10.jpg` and `predictions.jpg` are darknet's own detections on 10 validation images
(`01_dataset/scripts/save_10_predictions.ps1`, threshold 0.25). They are the visual reference for what
the hardware should produce.

## Network summary (416×416 input, 21 conv layers, ~3.40 GMAC/frame)

| # | Layer | Output | Notes |
|---|---|---|---|
| 0–1 | conv3×3 s2 | 208², 104² | stem |
| 2–9 | CSP block 1 | 104² → pooled 52² | route groups=2 (group-split), concat, maxpool |
| 10–17 | CSP block 2 | 52² → pooled 26² | |
| 18–25 | CSP block 3 | 26² → pooled 13² | layer 23 feeds two concats |
| 26–30 | head 1 | 13×13×36 | anchors (81,82) (135,169) (344,319) |
| 31–37 | 1×1, upsample ×2, concat with L23, head 2 | 26×26×36 | anchors (10,14) (23,27) (37,58) |

36 channels per head = 3 anchors × (4 box + 1 objectness + 7 classes). Activation: leaky 0.1, BN
folded, `scale_x_y = 1.05`. Darknet resizes the input to 416×416 without letterboxing.
