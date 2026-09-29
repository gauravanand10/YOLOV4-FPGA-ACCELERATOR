from pathlib import Path
import random
from collections import defaultdict

from pycocotools.coco import COCO

ROOT = Path(r"E:\yolo_mpsoc")
ANN = ROOT / "dataset" / "downloads" / "annotations" / "instances_train2017.json"

SEED = 42
TRAIN_COUNT = 8000
VALID_COUNT = 2000

CLASSES = [
    "person",
    "car",
    "bicycle",
    "bottle",
    "chair",
    "laptop",
    "cup",
]

random.seed(SEED)

coco = COCO(str(ANN))

cat_ids = {
    name: coco.getCatIds(catNms=[name])[0]
    for name in CLASSES
}

# Images belonging to each class
class_images = {}

for name, cat_id in cat_ids.items():
    class_images[name] = set(coco.getImgIds(catIds=[cat_id]))

print("\nCandidate images:")
print("-----------------")

for name in CLASSES:
    print(f"{name:12}: {len(class_images[name]):6}")

# Build union
all_images = set()

for ids in class_images.values():
    all_images.update(ids)

print(f"\nTotal candidate images: {len(all_images)}")

# Greedy balanced selection.
# First make sure every class contributes images.
selected = set()

remaining = {name: set(ids) for name, ids in class_images.items()}

target = TRAIN_COUNT + VALID_COUNT

while len(selected) < target:

    # Pick the currently least represented class.
    selected_counts = {
        name: len(selected & class_images[name])
        for name in CLASSES
    }

    target_class = min(
        CLASSES,
        key=lambda name: selected_counts[name]
    )

    candidates = list(remaining[target_class] - selected)

    if not candidates:
        break

    image_id = random.choice(candidates)
    selected.add(image_id)

print(f"\nSelected images: {len(selected)}")

selected = list(selected)
random.shuffle(selected)

train_ids = selected[:TRAIN_COUNT]
valid_ids = selected[TRAIN_COUNT:TRAIN_COUNT + VALID_COUNT]

out_dir = ROOT / "dataset"

train_file = out_dir / "selected_train_ids.txt"
valid_file = out_dir / "selected_valid_ids.txt"

with open(train_file, "w") as f:
    for image_id in sorted(train_ids):
        f.write(f"{image_id}\n")

with open(valid_file, "w") as f:
    for image_id in sorted(valid_ids):
        f.write(f"{image_id}\n")

print(f"\nTraining images : {len(train_ids)}")
print(f"Validation images: {len(valid_ids)}")

print("\nSaved:")
print(train_file)
print(valid_file)

print("\nClass coverage:")
print("----------------")

for name in CLASSES:
    train_coverage = len(set(train_ids) & class_images[name])
    valid_coverage = len(set(valid_ids) & class_images[name])

    print(
        f"{name:12}: "
        f"train={train_coverage:5}, "
        f"valid={valid_coverage:5}"
    )