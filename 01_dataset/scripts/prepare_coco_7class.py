from pathlib import Path
import json
import urllib.request
import zipfile

ROOT = Path(r"E:\yolo_mpsoc")
DATASET = ROOT / "dataset"
DOWNLOADS = DATASET / "downloads"

DOWNLOADS.mkdir(parents=True, exist_ok=True)

print("COCO 7-class dataset preparation")
print("--------------------------------")

# COCO categories we want
CLASSES = [
    "person",
    "car",
    "bicycle",
    "bottle",
    "chair",
    "laptop",
    "cup",
]

print("\nClasses:")
for i, name in enumerate(CLASSES):
    print(f"{i}: {name}")

print("\nNext step will download COCO annotations and selected images.")
print("No images have been downloaded by this script yet.")