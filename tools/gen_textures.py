"""Generates the seamless world textures used by Party Dash (assets/textures/*.png).

All tiles are grayscale/white so a Roblox Texture.Color3 can tint them (Color3 multiplies the image).
Run: python3 tools/gen_textures.py
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'textures')
os.makedirs(OUT, exist_ok=True)
S = 256  # every tile is 256x256


def save(img, name):
    img.save(os.path.join(OUT, name))
    print('wrote', name)


def bevel_tile(n=1, base=232, light=255, dark=178, edge=10, gap=3):
    """n x n beveled blocks (voxel/brick-top look like the reference lobby grass)."""
    img = Image.new('RGBA', (S, S), (base, base, base, 255))
    d = ImageDraw.Draw(img)
    cell = S // n
    for i in range(n):
        for j in range(n):
            x0, y0 = i * cell, j * cell
            x1, y1 = x0 + cell - 1, y0 + cell - 1
            # dark seam
            d.rectangle([x0, y0, x1, y1], fill=(dark - 30, dark - 30, dark - 30, 255))
            d.rectangle([x0 + gap, y0 + gap, x1 - gap, y1 - gap], fill=(base, base, base, 255))
            # light top-left bevel, dark bottom-right bevel
            for k in range(edge):
                t = 1 - k / edge
                lc = int(base + (light - base) * t)
                dc = int(base - (base - dark) * t)
                d.line([x0 + gap + k, y0 + gap + k, x1 - gap - k, y0 + gap + k], fill=(lc, lc, lc, 255))
                d.line([x0 + gap + k, y0 + gap + k, x0 + gap + k, y1 - gap - k], fill=(lc, lc, lc, 255))
                d.line([x0 + gap + k, y1 - gap - k, x1 - gap - k, y1 - gap - k], fill=(dc, dc, dc, 255))
                d.line([x1 - gap - k, y0 + gap + k, x1 - gap - k, y1 - gap - k], fill=(dc, dc, dc, 255))
    return img


def studs(n=2):
    """n x n LEGO studs per tile."""
    img = Image.new('RGBA', (S, S), (236, 236, 236, 255))
    cell = S // n
    shadow = Image.new('L', (S, S), 0)
    sd = ImageDraw.Draw(shadow)
    for i in range(n):
        for j in range(n):
            cx, cy = i * cell + cell / 2, j * cell + cell / 2
            r = cell * 0.30
            sd.ellipse([cx - r + 6, cy - r + 8, cx + r + 6, cy + r + 8], fill=120)
    shadow = shadow.filter(ImageFilter.GaussianBlur(6))
    dark = Image.new('RGBA', (S, S), (150, 150, 150, 255))
    img = Image.composite(dark, img, shadow)
    d = ImageDraw.Draw(img)
    for i in range(n):
        for j in range(n):
            cx, cy = i * cell + cell / 2, j * cell + cell / 2
            r = cell * 0.30
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(250, 250, 250, 255), outline=(196, 196, 196, 255), width=3)
            # highlight arc
            d.arc([cx - r * 0.75, cy - r * 0.75, cx + r * 0.75, cy + r * 0.75], 190, 260, fill=(255, 255, 255, 255), width=6)
    return img


def checker(a=255, b=222):
    img = Image.new('RGBA', (S, S), (a, a, a, 255))
    d = ImageDraw.Draw(img)
    h = S // 2
    d.rectangle([h, 0, S - 1, h - 1], fill=(b, b, b, 255))
    d.rectangle([0, h, h - 1, S - 1], fill=(b, b, b, 255))
    return img


def bricks(rows=4, cols=2, base=226, mortar=165):
    img = Image.new('RGBA', (S, S), (mortar, mortar, mortar, 255))
    d = ImageDraw.Draw(img)
    rh = S // rows
    bw = S // cols
    g = 5
    for r in range(rows):
        off = (bw // 2) if r % 2 else 0
        for c in range(-1, cols + 1):
            x0 = c * bw + off
            y0 = r * rh
            shade = base + random.Random(r * 31 + c).randint(-10, 8)
            d.rectangle([x0 + g, y0 + g, x0 + bw - g, y0 + rh - g], fill=(shade, shade, shade, 255))
            d.line([x0 + g, y0 + g, x0 + bw - g, y0 + g], fill=(250, 250, 250, 255), width=4)
            d.line([x0 + g, y0 + rh - g, x0 + bw - g, y0 + rh - g], fill=(shade - 40, shade - 40, shade - 40, 255), width=4)
    return img


def planks(n=4, base=222):
    img = Image.new('RGBA', (S, S), (150, 150, 150, 255))
    d = ImageDraw.Draw(img)
    pw = S // n
    rnd = random.Random(7)
    for i in range(n):
        x0 = i * pw
        shade = base + rnd.randint(-12, 10)
        d.rectangle([x0 + 3, 0, x0 + pw - 3, S], fill=(shade, shade, shade, 255))
        # grain
        for _ in range(6):
            gx = x0 + rnd.randint(8, pw - 8)
            d.line([gx, 0, gx + rnd.randint(-6, 6), S], fill=(shade - 18, shade - 18, shade - 18, 255), width=2)
        # cross seam at a staggered height
        sy = (i * 97) % S
        d.line([x0 + 3, sy, x0 + pw - 3, sy], fill=(140, 140, 140, 255), width=4)
    return img


def waves():
    """Cartoon caustic network (seamless Voronoi edges) on transparency, overlaid on turquoise water like ref1."""
    import numpy as np
    rnd = np.random.default_rng(5)
    pts = []
    while len(pts) < 16:  # poisson-ish sampling with wraparound so cells are even (no smudgy vertices)
        c = rnd.uniform(0, S, size=2)
        if all(min(abs(c[0] - q[0]), S - abs(c[0] - q[0])) ** 2 + min(abs(c[1] - q[1]), S - abs(c[1] - q[1])) ** 2 > 52**2 for q in pts):
            pts.append(c)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    best1 = np.full((S, S), 1e9, np.float32)
    best2 = np.full((S, S), 1e9, np.float32)
    for px, py in pts:
        for ox in (-S, 0, S):
            for oy in (-S, 0, S):
                dist = np.hypot(xx - (px + ox), yy - (py + oy))
                best2 = np.where(dist < best1, best1, np.minimum(best2, dist))
                best1 = np.minimum(best1, dist)
    edge = best2 - best1
    alpha = np.clip((7.0 - edge) / 3.0, 0, 1) * 200
    arr = np.zeros((S, S, 4), np.uint8)
    arr[..., 0:3] = 255
    arr[..., 3] = alpha.astype(np.uint8)
    return Image.fromarray(arr).filter(ImageFilter.GaussianBlur(0.8))


def hazard():
    img = Image.new('RGBA', (S, S), (255, 255, 255, 255))
    d = ImageDraw.Draw(img)
    w = S // 4
    for k in range(-4, 8):
        x = k * w * 2
        d.polygon([(x, 0), (x + w, 0), (x + w + S, S), (x + S, S)], fill=(40, 40, 40, 255))
    return img


def grass_blades():
    """Subtle speckle noise for grass/dirt variety (tinted)."""
    img = Image.new('RGBA', (S, S), (238, 238, 238, 255))
    d = ImageDraw.Draw(img)
    rnd = random.Random(11)
    for _ in range(420):
        x, y = rnd.randint(0, S - 1), rnd.randint(0, S - 1)
        c = rnd.choice([255, 220, 205])
        d.rectangle([x, y, x + 3, y + 3], fill=(c, c, c, 255))
    return img


random.seed(1)
save(bevel_tile(1), 'tile_bevel.png')        # one beveled block per tile
save(bevel_tile(2, edge=8), 'tile_bevel_2x2.png')
save(studs(2), 'studs.png')
save(checker(), 'checker.png')
save(checker(255, 236), 'checker_soft.png')
save(bricks(), 'bricks.png')
save(planks(), 'planks.png')
save(waves(), 'waves.png')
save(hazard(), 'hazard.png')
save(grass_blades(), 'speckle.png')

def grass_top():
    """2x2 bevel tiles with the two diagonal cells 8% darker: a beveled checker (ref2/ref4) in one layer."""
    img = bevel_tile(2, edge=8)
    px = img.load()
    h = S // 2
    for x in range(S):
        for y in range(S):
            if (x < h) == (y < h):
                r, g, b, a = px[x, y]
                px[x, y] = (int(r * 0.92), int(g * 0.92), int(b * 0.92), a)
    return img


def stone_blocks():
    """Irregular large stone blocks: 3 rows, random widths, mortar 150, blocks 205-235, bevelled."""
    img = Image.new('RGBA', (S, S), (150, 150, 150, 255))
    d = ImageDraw.Draw(img)
    rnd = random.Random(21)
    rows = 3
    rh = S // rows
    g = 3
    for r in range(rows):
        x = -rnd.randint(0, 60)
        while x < S:
            w = rnd.randint(60, 140)
            shade = rnd.randint(205, 235)
            for ox in (0, S, -S):
                x0, x1 = x + ox, x + ox + w
                y0, y1 = r * rh, (r + 1) * rh
                d.rectangle([x0 + g, y0 + g, x1 - g, y1 - g], fill=(shade, shade, shade, 255))
                d.line([x0 + g, y0 + g, x1 - g, y0 + g], fill=(250, 250, 250, 255), width=4)
                d.line([x0 + g, y0 + g, x0 + g, y1 - g], fill=(244, 244, 244, 255), width=3)
                d.line([x0 + g, y1 - g, x1 - g, y1 - g], fill=(shade - 45, shade - 45, shade - 45, 255), width=4)
                d.line([x1 - g, y0 + g, x1 - g, y1 - g], fill=(shade - 35, shade - 35, shade - 35, 255), width=3)
            x += w
    return img


def awning():
    """Vertical stripes: 2 white + 2 gray-90 (tint red -> red/white candy stripes)."""
    img = Image.new('RGBA', (S, S), (255, 255, 255, 255))
    d = ImageDraw.Draw(img)
    w = S // 4
    for i in (1, 3):
        d.rectangle([i * w, 0, (i + 1) * w - 1, S], fill=(90, 90, 90, 255))
    return img


def laser_dash():
    img = Image.new('RGBA', (64, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 26, 15], fill=(255, 255, 255, 255))
    return img


def stripes_diag():
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = 24
    for k in range(-12, 12):
        x = k * w * 2
        d.polygon([(x, 0), (x + w, 0), (x + w + S, S), (x + S, S)], fill=(255, 255, 255, 255))
    return img


def glow_soft():
    import numpy as np
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    r = np.hypot(xx - S / 2, yy - S / 2) / (S / 2)
    t = np.clip(1 - r, 0, 1)
    a = t * t * (3 - 2 * t)
    arr = np.zeros((S, S, 4), np.uint8)
    arr[..., 0:3] = 255
    arr[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(arr)


save(grass_top(), 'grass_top.png')
save(stone_blocks(), 'stone_blocks.png')
save(awning(), 'awning.png')
save(laser_dash(), 'laser_dash.png')
save(stripes_diag(), 'stripes_diag.png')
save(glow_soft(), 'glow_soft.png')
