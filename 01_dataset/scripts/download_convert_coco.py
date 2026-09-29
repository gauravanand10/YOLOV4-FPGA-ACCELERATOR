from pathlib import Path
import json
import urllib.request
import time

from pycocotools.coco import COCO

ROOT = Path(r"E:\yolo_mpsoc")
DATASET = ROOT / "dataset"

ANN_FILE = (
    DATASET
    / "downloads"
    / "annotations"
    / "instances_train2017.json"
)

TRAIN_IDS_FILE = DATASET / "selected_train_ids.txt"
VALID_IDS_FILE = DATASET / "selected_valid_ids.txt"

CLASSES = [
    "person",
    "car",
    "bicycle",
    "bottle",
    "chair",
    "laptop",
    "cup",
]

# COCO category ID -> our YOLO class ID
CAT_TO_CLASS = {}

coco = COCO(str(ANN_FILE))

for class_id, name in enumerate(CLASSES):
    cat_ids = coco.getCatIds(catNms=[name])

    if not cat_ids:
        raise RuntimeError(f"COCO class not found: {name}")

    CAT_TO_CLASS[cat_ids[0]] = class_id


def read_ids(path):
    with open(path, "r") as f:
        return [int(x.strip()) for x in f if x.strip()]


train_ids = read_ids(TRAIN_IDS_FILE)
valid_ids = read_ids(VALID_IDS_FILE)

print("\nCOCO → Darknet conversion")
print("=========================")
print(f"Training images   : {len(train_ids)}")
print(f"Validation images : {len(valid_ids)}")

print("\nClass mapping:")
for cat_id, class_id in CAT_TO_CLASS.items():
    print(
        f"COCO {cat_id:3} -> "
        f"YOLO {class_id}: {CLASSES[class_id]}"
    )


def process_split(image_ids, split):

    image_dir = DATASET / "images" / split
    label_dir = DATASET / "labels" / split

    image_dir.mkdir(parents=True, exist_ok=True)
    label_dir.mkdir(parents=True, exist_ok=True)

    processed = 0
    failed = 0
    empty = 0

    for index, image_id in enumerate(image_ids, start=1):

        img_info = coco.loadImgs(image_id)[0]

        file_name = img_info["file_name"]
        width = img_info["width"]
        height = img_info["height"]

        image_path = image_dir / file_name
        label_path = label_dir / (
            Path(file_name).stem + ".txt"
        )

        # ------------------------------------------
        # Download image
        # ------------------------------------------

        if not image_path.exists():

            url = (
                "http://images.cocodataset.org/"
                f"train2017/{file_name}"
            )

            try:
                urllib.request.urlretrieve(
                    url,
                    image_path
                )

            except Exception as e:

                failed += 1

                print(
                    f"\nDOWNLOAD FAILED: "
                    f"{file_name} -> {e}"
                )

                continue

        # ------------------------------------------
        # Get annotations
        # ------------------------------------------

        ann_ids = coco.getAnnIds(
            imgIds=[image_id],
            catIds=list(CAT_TO_CLASS.keys()),
            iscrowd=None,
        )

        annotations = coco.loadAnns(ann_ids)

        lines = []

        for ann in annotations:

            category_id = ann["category_id"]

            if category_id not in CAT_TO_CLASS:
                continue

            x, y, w, h = ann["bbox"]

            # Clip bounding box to image
            x = max(0, x)
            y = max(0, y)

            w = min(w, width - x)
            h = min(h, height - y)

            if w <= 0 or h <= 0:
                continue

            # COCO xywh -> YOLO normalized cx cy w h
            cx = (x + w / 2) / width
            cy = (y + h / 2) / height
            nw = w / width
            nh = h / height

            class_id = CAT_TO_CLASS[category_id]

            lines.append(
                f"{class_id} "
                f"{cx:.6f} "
                f"{cy:.6f} "
                f"{nw:.6f} "
                f"{nh:.6f}"
            )

        # ------------------------------------------
        # Save labels
        # ------------------------------------------

        with open(label_path, "w") as f:
            f.write("\n".join(lines))

        if not lines:
            empty += 1

        processed += 1

        if index % 100 == 0 or index == len(image_ids):

            print(
                f"\r{split}: "
                f"{index}/{len(image_ids)} "
                f"processed | "
                f"failed={failed}",
                end="",
                flush=True,
            )

    print()

    return processed, failed, empty


print("\nProcessing training set...")
train_result = process_split(train_ids, "train")

print("\nProcessing validation set...")
valid_result = process_split(valid_ids, "valid")

print("\n=========================")
print("DATASET PREPARATION DONE")
print("=========================")

print(
    f"Train: "
    f"processed={train_result[0]}, "
    f"failed={train_result[1]}, "
    f"empty={train_result[2]}"
)

print(
    f"Valid: "
    f"processed={valid_result[0]}, "
    f"failed={valid_result[1]}, "
    f"empty={valid_result[2]}"
)

# ------------------------------------------
# Create Darknet train.txt / valid.txt
# ------------------------------------------

train_txt = DATASET / "train.txt"
valid_txt = DATASET / "valid.txt"

with open(train_txt, "w") as f:

    for image_id in train_ids:

        info = coco.loadImgs(image_id)[0]

        image_path = (
            DATASET
            / "images"
            / "train"
            / info["file_name"]
        )

        if image_path.exists():
            f.write(str(image_path.resolve()).replace("\\", "/") + "\n")


with open(valid_txt, "w") as f:

    for image_id in valid_ids:

        info = coco.loadImgs(image_id)[0]

        image_path = (
            DATASET
            / "images"
            / "valid"
            / info["file_name"]
        )

        if image_path.exists():
            f.write(str(image_path.resolve()).replace("\\", "/") + "\n")


print("\nCreated:")
print(train_txt)
print(valid_txt)