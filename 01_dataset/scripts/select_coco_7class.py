from pathlib import Path
from pycocotools.coco import COCO

ROOT = Path(r"E:\yolo_mpsoc")
ANN = ROOT / "dataset" / "downloads" / "annotations" / "instances_train2017.json"

CLASSES = [
    "person",
    "car",
    "bicycle",
    "bottle",
    "chair",
    "laptop",
    "cup",
]

coco = COCO(str(ANN))

print("\nCOCO category IDs")
print("-----------------")

cat_ids = {}

for name in CLASSES:
    ids = coco.getCatIds(catNms=[name])

    if not ids:
        raise RuntimeError(f"COCO category not found: {name}")

    cat_ids[name] = ids[0]
    print(f"{name:12} -> {ids[0]}")

print("\nImages containing each class")
print("----------------------------")

all_image_ids = set()

for name, cat_id in cat_ids.items():
    image_ids = set(coco.getImgIds(catIds=[cat_id]))

    print(f"{name:12} -> {len(image_ids):6} images")

    all_image_ids.update(image_ids)

print("\nTotal unique images")
print("-------------------")
print(len(all_image_ids))

# Save the selected image IDs
output = ROOT / "dataset" / "coco_7class_image_ids.txt"

with open(output, "w") as f:
    for image_id in sorted(all_image_ids):
        f.write(f"{image_id}\n")

print(f"\nSaved image IDs to:")
print(output)