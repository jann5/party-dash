"""Difference matting: recovers a transparent PNG from two captures of the same image shown over pure black and
pure white (alpha = 1 - (white - black), color = black / alpha). Used to pull ChatGPT-generated transparent icon
sheets out of the browser via screenshots.

Usage: python3 tools/matte.py <over_black.png> <over_white.png> <out.png>
"""
import sys

import numpy as np
from PIL import Image

b = np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(np.float32) / 255
w = np.asarray(Image.open(sys.argv[2]).convert('RGB')).astype(np.float32) / 255
diff = np.clip(w - b, 0, 1).mean(axis=2)
alpha = 1 - diff
alpha = np.where(alpha < 0.05, 0, alpha)  # kill JPEG/scaling noise in empty areas
alpha = np.where(alpha > 0.96, 1, alpha)
safe = np.maximum(alpha, 1e-3)[..., None]
rgb = np.clip(b / safe, 0, 1)
out = np.dstack([rgb, alpha]) * 255
Image.fromarray(out.astype(np.uint8)).save(sys.argv[3])
print('wrote', sys.argv[3])
