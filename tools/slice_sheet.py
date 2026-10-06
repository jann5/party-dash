"""Slices a ChatGPT icon sheet (transparent PNG laid out as a R x C grid) into individual square icons.

Usage: python3 tools/slice_sheet.py <sheet.png> <rows> <cols> <name1,name2,...> [size]
Connected alpha blobs are assigned to the grid cell that contains their centroid (so an icon that pokes over a
cell border stays whole and neighbours never bleed in); each icon is cropped, padded to a square and resized.
Use "-" as a name to skip a cell.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sheet, rows, cols, names = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4].split(',')
size = int(sys.argv[5]) if len(sys.argv) > 5 else 256
out_dir = os.path.join(os.path.dirname(__file__), '..', 'assets', 'icons')
os.makedirs(out_dir, exist_ok=True)
im = Image.open(sheet).convert('RGBA')
arr = np.asarray(im)
H, W = arr.shape[:2]
mask = arr[..., 3] > 24
labels, n = ndimage.label(mask)
objs = ndimage.find_objects(labels)
areas = ndimage.sum(mask, labels, range(1, n + 1))
cells = {}
for idx in range(n):
    if areas[idx] < 60:  # specks / sparkles far from anything: ignore unless inside a cell's main bbox later
        continue
    sl = objs[idx]
    cy, cx = ndimage.center_of_mass(mask, labels, idx + 1)
    r, c = min(rows - 1, int(cy / (H / rows))), min(cols - 1, int(cx / (W / cols)))
    y0, y1, x0, x1 = sl[0].start, sl[0].stop, sl[1].start, sl[1].stop
    cells.setdefault((r, c), []).append((y0, y1, x0, x1, idx + 1))
for k, name in enumerate(names):
    if not name or name == '-':
        continue
    r, c = divmod(k, cols)
    blobs = cells.get((r, c))
    if not blobs:
        print('empty cell', name)
        continue
    y0 = min(b[0] for b in blobs); y1 = max(b[1] for b in blobs)
    x0 = min(b[2] for b in blobs); x1 = max(b[3] for b in blobs)
    keep = np.isin(labels[y0:y1, x0:x1], [b[4] for b in blobs])
    # keep small sparkles that sit inside this icon's box too
    small = (labels[y0:y1, x0:x1] > 0) & ~keep
    for lab in np.unique(labels[y0:y1, x0:x1][small]):
        if lab and areas[lab - 1] < 60:
            keep |= labels[y0:y1, x0:x1] == lab
    crop = arr[y0:y1, x0:x1].copy()
    crop[..., 3] = np.where(keep | (crop[..., 3] <= 24), crop[..., 3], 0) * (keep | (crop[..., 3] <= 24))
    # soft edge pixels (alpha <= 24) that belong to neighbours: drop them outside a 3px dilation of the kept mask
    near = ndimage.binary_dilation(keep, iterations=3)
    crop[..., 3] = np.where(near, crop[..., 3], 0)
    icon = Image.fromarray(crop)
    side = int(max(icon.size) * 1.08)
    sq = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    sq.paste(icon, ((side - icon.size[0]) // 2, (side - icon.size[1]) // 2))
    sq = sq.resize((size, size), Image.LANCZOS)
    sq.save(os.path.join(out_dir, name + '.png'))
    print('wrote', name, (x0, y0, x1, y1))
