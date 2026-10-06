"""Draws the Wheel of Fortune face (assets/art/wheel_face.png, 1024 px, transparent outside the disc).

8 equal wedges in the Theme colours (Red, Yellow, Blue, Green, Purple, Orange, Cyan, Pink), white separators and a
thick ink rim. Wedge 1 is centred at the TOP (12 o'clock) and they go clockwise, so wheel slice i (1-based) sits
at angle (i - 1) * 45 degrees clockwise from the top. Prize icons are separate ImageLabels on top (UI piece).
Run: python3 tools/gen_wheel.py
"""
import math
import os

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'art', 'wheel_face.png')
N = 1024
SS = 2
S = N * SS
COLORS = [(235, 48, 58), (255, 211, 38), (36, 122, 246), (62, 208, 72), (138, 72, 240), (255, 138, 28), (28, 196, 245), (255, 78, 166)]
img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
c = S / 2
R = S / 2 - 6 * SS
for i, col in enumerate(COLORS):
    # PIL angles: 0 = 3 o'clock, clockwise. Wedge i centred at top (-90) + i*45.
    a0 = -90 + i * 45 - 22.5
    d.pieslice([c - R, c - R, c + R, c + R], a0, a0 + 45, fill=col + (255,))
    # soft inner highlight on the upper half of each wedge
    hl = tuple(min(255, int(v + (255 - v) * 0.18)) for v in col)
    d.pieslice([c - R * 0.98, c - R * 0.98, c + R * 0.98, c + R * 0.98], a0 + 2, a0 + 22.5, fill=hl + (255,))
for i in range(8):
    a = math.radians(-90 + i * 45 - 22.5)
    d.line([c, c, c + R * math.cos(a), c + R * math.sin(a)], fill=(255, 255, 255, 255), width=6 * SS)
d.ellipse([c - R, c - R, c + R, c + R], outline=(22, 18, 36, 255), width=10 * SS)
hub = R * 0.13
d.ellipse([c - hub, c - hub, c + hub, c + hub], fill=(255, 196, 30, 255), outline=(22, 18, 36, 255), width=6 * SS)
img = img.resize((N, N), Image.LANCZOS)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT)
print('wrote', OUT)
