"""Offline preview renderer for scenes exported by tools/scene_export.luau.

Studio stops drawing the 3D viewport while the Mac screen is locked, so builders/critics use this to SEE a map:
flat-shaded parts (painter's algorithm, sun + ambient, Neon unlit, darker edge lines so blocks read), the sea plane
and a sky gradient. It is a layout/colour/contrast preview, not a Roblox-accurate render (no textures, no shadows).

Usage:
  python3 tools/render_scene.py scene.json out.png [--view iso|top|eye|low] [--yaw DEG] [--pitch DEG]
                                   [--dist STUDS] [--target X,Y,Z] [--eye X,Y,Z] [--fov 70] [--size 1280x720]
Default: --view iso (3/4 view from the south-east, 35 deg down, framing every part).
Run several views to judge a map: iso (overview), top (layout), eye (what a player sees from a spawn).
"""
import argparse
import json
import math

import numpy as np
from PIL import Image, ImageDraw

SUN = np.array([-0.45, 0.85, -0.30])
SUN = SUN / np.linalg.norm(SUN)


def unit_shape(shape):
    """Polygons (list of Nx3 arrays) of a unit part centered at the origin with size 1x1x1."""
    h = 0.5
    if shape in ('Block', 'Mesh', 'Truss', 'Union'):
        v = np.array([[x, y, z] for x in (-h, h) for y in (-h, h) for z in (-h, h)])
        faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        return [v[list(f)] for f in faces]
    if shape in ('Wedge', 'CornerWedge'):
        # Roblox WedgePart: bottom full, back (+Z) face full height, slope from top-back to bottom-front (-Z)
        b = [(-h, -h, -h), (h, -h, -h), (h, -h, h), (-h, -h, h)]
        t = [(-h, h, h), (h, h, h)]
        polys = [
            [b[0], b[1], b[2], b[3]],  # bottom
            [b[3], b[2], t[1], t[0]],  # back
            [b[0], t[0], t[1], b[1]],  # slope
            [b[0], b[3], t[0]],  # left tri
            [b[1], t[1], b[2]],  # right tri
        ]
        return [np.array(p, dtype=float) for p in polys]
    if shape == 'Cylinder':  # axis along X
        n = 20
        ang = np.linspace(0, 2 * math.pi, n, endpoint=False)
        ring = np.stack([np.cos(ang) * h, np.sin(ang) * h], axis=1)
        polys = []
        for i in range(n):
            a, b2 = ring[i], ring[(i + 1) % n]
            polys.append(np.array([[-h, a[0], a[1]], [h, a[0], a[1]], [h, b2[0], b2[1]], [-h, b2[0], b2[1]]]))
        polys.append(np.array([[h, p[0], p[1]] for p in ring]))
        polys.append(np.array([[-h, p[0], p[1]] for p in ring[::-1]]))
        return polys
    if shape == 'Ball':
        polys = []
        nu, nv = 14, 9
        for i in range(nu):
            for j in range(nv):
                def pt(u, v):
                    th = 2 * math.pi * u / nu
                    ph = math.pi * v / nv
                    return [h * math.sin(ph) * math.cos(th), h * math.cos(ph), h * math.sin(ph) * math.sin(th)]
                polys.append(np.array([pt(i, j), pt(i + 1, j), pt(i + 1, j + 1), pt(i, j + 1)]))
        return polys
    return unit_shape('Block')


SHAPES = {}


def part_polys(p):
    sh = p.get('sh', 'Block')
    if sh not in SHAPES:
        SHAPES[sh] = unit_shape(sh)
    size = np.array(p['s'], dtype=float)
    if sh == 'Ball':
        d = min(size)
        size = np.array([d, d, d])
    cf = p['cf']
    pos = np.array(cf[0:3])
    rot = np.array(cf[3:12]).reshape(3, 3)
    out = []
    for poly in SHAPES[sh]:
        local = poly * size
        world = local @ rot.T + pos
        out.append(world)
    return out


def look_at(eye, target):
    f = target - eye
    f = f / np.linalg.norm(f)
    up = np.array([0.0, 1.0, 0.0])
    r = np.cross(f, up)
    if np.linalg.norm(r) < 1e-6:
        r = np.array([1.0, 0.0, 0.0])
    r = r / np.linalg.norm(r)
    u = np.cross(r, f)
    return r, u, f


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('scene')
    ap.add_argument('out')
    ap.add_argument('--view', default='iso')
    ap.add_argument('--yaw', type=float, default=None)
    ap.add_argument('--pitch', type=float, default=None)
    ap.add_argument('--dist', type=float, default=None)
    ap.add_argument('--target', default=None)
    ap.add_argument('--eye', default=None)
    ap.add_argument('--fov', type=float, default=70)
    ap.add_argument('--size', default='1280x720')
    a = ap.parse_args()
    W, H = (int(x) for x in a.size.split('x'))
    SS = 2
    data = json.load(open(a.scene))
    parts = data['parts']
    if not parts:
        raise SystemExit('no parts in scene')
    pts = np.array([p['cf'][0:3] for p in parts])
    lo, hi = np.percentile(pts, 2, axis=0), np.percentile(pts, 98, axis=0)
    center = (lo + hi) / 2
    radius = max(20.0, float(np.linalg.norm(hi - lo)) / 2)
    target = np.array([float(x) for x in a.target.split(',')]) if a.target else center
    ortho = a.view == 'top'
    if a.eye:
        eye = np.array([float(x) for x in a.eye.split(',')])
    else:
        yaw = math.radians(a.yaw if a.yaw is not None else {'iso': 225, 'low': 200, 'eye': 180, 'top': 180}.get(a.view, 225))
        pitch = math.radians(a.pitch if a.pitch is not None else {'iso': 35, 'low': 12, 'eye': 15, 'top': 89.9}.get(a.view, 35))
        dist = a.dist or radius * (2.1 if a.view in ('iso', 'low') else 1.2)
        eye = target + dist * np.array([math.cos(pitch) * math.sin(yaw), math.sin(pitch), math.cos(pitch) * math.cos(yaw)])
    r, u, f = look_at(eye, target)
    focal = (H * SS / 2) / math.tan(math.radians(a.fov) / 2)
    ortho_scale = (H * SS / 2) / (radius * 1.15)

    img = Image.new('RGB', (W * SS, H * SS))
    sky = ImageDraw.Draw(img)
    for y in range(H * SS):
        t = y / (H * SS)
        c = (int(70 + 110 * t), int(160 + 70 * t), int(250 - 10 * t))
        sky.line([(0, y), (W * SS, y)], fill=c)

    polys = []  # (depth, screen_pts, fill, outline, alpha)

    def project(world):
        rel = world - eye
        x, y, z = rel @ r, rel @ u, rel @ f
        if ortho:
            return np.stack([W * SS / 2 + x * ortho_scale, H * SS / 2 - y * ortho_scale], axis=1), z
        if np.any(z < 0.5):
            return None, z
        return np.stack([W * SS / 2 + x / z * focal, H * SS / 2 - y / z * focal], axis=1), z

    sea = data.get('sea')
    if sea is not None and eye[1] > sea:
        # No roll, so the horizon is a horizontal screen line; every row below it looks down onto the sea.
        sky = ImageDraw.Draw(img)
        if ortho:
            v_h = -1
        else:
            v_h = (H * SS / 2) + (f[1] * focal / u[1] if abs(u[1]) > 1e-6 else -1e9)
        top = int(max(0, min(H * SS, math.floor(v_h) + 1)))
        for y in range(top, H * SS):
            t = min(1.0, (y - top) / (0.6 * H * SS) + 0.05)
            sky.line([(0, y), (W * SS, y)], fill=(int(120 - 85 * t), int(225 - 25 * t), int(240 - 15 * t)))

    for p in parts:
        col = np.array(p['c']) * 255
        mat = p.get('m', 'Plastic')
        alpha = int(255 * (1 - p.get('t', 0)))
        if mat == 'Glass':
            alpha = min(alpha, 150)
        if mat == 'ForceField':
            continue
        for world in part_polys(p):
            n = np.cross(world[1] - world[0], world[2] - world[0])
            nl = np.linalg.norm(n)
            if nl < 1e-9:
                continue
            n = n / nl
            to_eye = (eye - world.mean(axis=0)) if not ortho else -f
            if alpha == 255 and np.dot(n, to_eye) <= 0:
                continue
            sp, z = project(world)
            if sp is None:
                continue
            if mat == 'Neon':
                shade = 1.25
            else:
                shade = 0.58 + 0.48 * max(0.0, float(np.dot(n, SUN)))
            fill = tuple(int(min(255, c * shade)) for c in col)
            outline = tuple(int(c * 0.72) for c in fill)
            polys.append((float(np.mean(z)), sp, fill, outline, alpha))

    polys.sort(key=lambda t: -t[0])
    base = img.convert('RGBA')
    draw = ImageDraw.Draw(base, 'RGBA')
    for depth, sp, fill, outline, alpha in polys:
        pts2 = [tuple(map(float, q)) for q in sp]
        if alpha >= 255:
            draw.polygon(pts2, fill=fill + (255,), outline=(outline + (255,)) if outline else None)
        else:
            draw.polygon(pts2, fill=fill + (alpha,))
    out = base.convert('RGB').resize((W, H), Image.LANCZOS)
    out.save(a.out)
    print(f'wrote {a.out}: {len(parts)} parts, {len(polys)} polygons, eye={np.round(eye, 1).tolist()} target={np.round(target, 1).tolist()}')


if __name__ == '__main__':
    main()
