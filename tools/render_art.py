#!/usr/bin/env python3
"""Render the addon's textures.

Everything here is original art generated from simple geometry, so the addon
ships no third-party images. Run from the repository root:

    python3 tools/render_art.py

Outputs (32-bit uncompressed TGA, which every WoW client can load):
    WaypointTracker/Media/Arrow.tga    108-frame 3D block arrow (9 x 12 cells of 112x84)
    WaypointTracker/Media/Arrived.tga  64-frame spinning "you are here" arrow (8x8 of 64px)
    WaypointTracker/Media/Pin.tga      map / minimap pin
    WaypointTracker/Media/Icon.tga     addon icon (TOC IconTexture, minimap button)
    docs/images/logo.png               400x400 logo for CurseForge / README

The textures are drawn in white/grey so the game can tint them with
SetVertexColor (that is how the arrow changes colour with distance).
"""

import math
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "WaypointTracker", "Media")
DOCS = os.path.join(ROOT, "docs", "images")

# ---------------------------------------------------------------------------
# Tiny software rasteriser (orthographic, z-buffered, flat shaded)
# ---------------------------------------------------------------------------


def normalize(v):
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v)
    return v / n if n else v


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=np.float64)


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=np.float64)


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float64)


def rasterize(tris, size, scale, light, ambient=0.30, diffuse=0.80, spec=0.30, shininess=16, height=None):
    """tris: list of (3x3 camera-space vertices, albedo).

    Camera space: x right, y up, z towards the viewer. Returns RGBA float image
    of size x height (height defaults to size).
    """
    width = size
    height = height or size
    img = np.zeros((height, width, 4), dtype=np.float64)
    zbuf = np.full((height, width), -1e9)
    half = width / 2.0
    halfh = height / 2.0
    view = np.array([0.0, 0.0, 1.0])
    ys, xs = np.mgrid[0:height, 0:width]
    px = xs + 0.5
    py = ys + 0.5
    for verts, albedo in tris:
        n = np.cross(verts[1] - verts[0], verts[2] - verts[0])
        if np.linalg.norm(n) == 0:
            continue
        n = normalize(n)
        if n[2] <= 0:  # back face
            continue
        diff = max(0.0, float(np.dot(n, light)))
        h = normalize(light + view)
        sp = max(0.0, float(np.dot(n, h))) ** shininess
        shade = min(1.0, ambient + diffuse * diff) * albedo + spec * sp
        shade = min(1.0, shade)
        # to pixel space
        sx = half + verts[:, 0] * scale
        sy = halfh - verts[:, 1] * scale
        sz = verts[:, 2]
        x0, x1 = int(max(0, math.floor(sx.min()))), int(min(width - 1, math.ceil(sx.max())))
        y0, y1 = int(max(0, math.floor(sy.min()))), int(min(height - 1, math.ceil(sy.max())))
        if x1 < x0 or y1 < y0:
            continue
        bx = px[y0:y1 + 1, x0:x1 + 1]
        by = py[y0:y1 + 1, x0:x1 + 1]
        (ax, ay), (bx_, by_), (cx, cy) = (sx[0], sy[0]), (sx[1], sy[1]), (sx[2], sy[2])
        den = (by_ - cy) * (ax - cx) + (cx - bx_) * (ay - cy)
        if abs(den) < 1e-12:
            continue
        w0 = ((by_ - cy) * (bx - cx) + (cx - bx_) * (by - cy)) / den
        w1 = ((cy - ay) * (bx - cx) + (ax - cx) * (by - cy)) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-9) & (w1 >= -1e-9) & (w2 >= -1e-9)
        depth = w0 * sz[0] + w1 * sz[1] + w2 * sz[2]
        zb = zbuf[y0:y1 + 1, x0:x1 + 1]
        mask = inside & (depth > zb)
        zb[mask] = depth[mask]
        region = img[y0:y1 + 1, x0:x1 + 1]
        region[mask, 0] = shade
        region[mask, 1] = shade
        region[mask, 2] = shade
        region[mask, 3] = 1.0
    return img


def downsample(img, factor):
    """Box-filter downsample with premultiplied alpha."""
    h, w, _ = img.shape
    pre = img.copy()
    pre[..., :3] *= pre[..., 3:4]
    pre = pre.reshape(h // factor, factor, w // factor, factor, 4).mean(axis=(1, 3))
    out = pre.copy()
    a = out[..., 3:4]
    out[..., :3] = np.where(a > 0, pre[..., :3] / np.maximum(a, 1e-9), 0)
    return out


def add_outline(img, radius=1.6, strength=0.9, shadow=True):
    """Put a dark rim (and a soft drop shadow) behind the shape.

    The rim stays dark after tinting, which keeps the arrow readable on
    bright snow or dark caves alike.
    """
    alpha = Image.fromarray((img[..., 3] * 255).astype(np.uint8), "L")
    size = int(math.ceil(radius)) * 2 + 1
    rim = alpha.filter(ImageFilter.MaxFilter(size)).filter(ImageFilter.GaussianBlur(radius * 0.35))
    rim = np.asarray(rim, dtype=np.float64) / 255.0 * strength
    if shadow:
        sh = alpha.filter(ImageFilter.GaussianBlur(radius * 1.6))
        sh = np.asarray(sh, dtype=np.float64) / 255.0 * 0.55
        sh = np.roll(np.roll(sh, 1, axis=0), 1, axis=1)
        rim = np.maximum(rim, sh)
    base = np.zeros_like(img)
    base[..., :3] = 0.04
    base[..., 3] = rim
    # composite img over base
    a = img[..., 3:4]
    out = np.empty_like(img)
    out_a = a + base[..., 3:4] * (1 - a)
    out[..., :3] = np.where(out_a > 0, (img[..., :3] * a + base[..., :3] * base[..., 3:4] * (1 - a)) / np.maximum(out_a, 1e-9), 0)
    out[..., 3:4] = out_a
    return out


def to_image(img):
    arr = np.clip(img * 255.0 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def save_tga(im, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, format="TGA", compression=None)
    print("wrote", os.path.relpath(path, ROOT), im.size)


# ---------------------------------------------------------------------------
# Arrow model: a faceted "navigation" arrow with a raised centre ridge
# ---------------------------------------------------------------------------

TIP = (0.0, 1.0)
RIGHT = (0.62, -0.62)
NOTCH = (0.0, -0.20)
LEFT = (-0.62, -0.62)
CENTRE = (0.0, 0.22)
Y_SHIFT = -0.19  # centre the arrow on its rotation point

TOP_Z = {"tip": 0.06, "wing": 0.04, "notch": 0.14, "centre": 0.40}
BOTTOM_Z = -0.10


def arrow_triangles():
    def p(xy, z):
        return np.array([xy[0], xy[1] + Y_SHIFT, z], dtype=np.float64)

    T = p(TIP, TOP_Z["tip"])
    R = p(RIGHT, TOP_Z["wing"])
    N = p(NOTCH, TOP_Z["notch"])
    L = p(LEFT, TOP_Z["wing"])
    C = p(CENTRE, TOP_Z["centre"])
    Tb, Rb, Nb, Lb = (p(TIP, BOTTOM_Z), p(RIGHT, BOTTOM_Z), p(NOTCH, BOTTOM_Z), p(LEFT, BOTTOM_Z))

    top = 1.0
    side = 0.60
    tris = [
        # four top facets (counter-clockwise when seen from above)
        (np.array([T, C, R]), top),
        (np.array([R, C, N]), top),
        (np.array([T, L, C]), top),
        (np.array([C, L, N]), top),
    ]
    # side walls: outline T -> R -> N -> L -> T (clockwise from above), extrude down
    outline = [(T, Tb), (R, Rb), (N, Nb), (L, Lb)]
    for i in range(4):
        a_top, a_bot = outline[i]
        b_top, b_bot = outline[(i + 1) % 4]
        tris.append((np.array([a_top, b_top, b_bot]), side))
        tris.append((np.array([a_top, b_bot, a_bot]), side))
    # bottom (rarely visible)
    tris.append((np.array([Tb, Nb, Rb]), 0.5))
    tris.append((np.array([Tb, Lb, Nb]), 0.5))
    return tris


def fix_winding(tris):
    """Make every triangle face outwards (away from the model centre)."""
    centre = np.array([0.0, 0.0, 0.0])
    fixed = []
    for verts, albedo in tris:
        n = np.cross(verts[1] - verts[0], verts[2] - verts[0])
        mid = verts.mean(axis=0)
        if np.dot(n, mid - centre) < 0:
            verts = verts[[0, 2, 1]]
        fixed.append((verts, albedo))
    return fixed


def render_arrow_frame(angle, cell, tilt_deg=44.0, ss=4):
    """angle: counter-clockwise screen rotation (radians); 0 = pointing up."""
    size = cell * ss
    model = fix_winding(arrow_triangles())
    # rotate on the ground, then tip the ground plane away from the camera
    m = rot_x(-math.radians(tilt_deg)) @ rot_z(angle)
    tris = [((m @ v.T).T, a) for v, a in model]
    light = normalize([-0.70, 0.45, 0.55])
    img = rasterize(tris, size, scale=size * 0.40, light=light)
    img = downsample(img, ss)
    img = add_outline(img, radius=1.7)
    return img


def render_arrow_sheet():
    frames, cols, cell, tex = 100, 10, 100, 1024
    sheet = np.zeros((tex, tex, 4), dtype=np.float64)
    for i in range(frames):
        ang = 2 * math.pi * i / frames
        f = render_arrow_frame(ang, cell)
        r, c = divmod(i, cols)
        sheet[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell] = f
    save_tga(to_image(sheet), os.path.join(MEDIA, "Arrow.tga"))
    return sheet


def render_arrived_sheet():
    """Arrow standing on its tip, spinning: shown when you reach the spot."""
    frames, cols, cell, tex, ss = 64, 8, 64, 512, 4
    sheet = np.zeros((tex, tex, 4), dtype=np.float64)
    model = fix_winding(arrow_triangles())
    light = normalize([-0.5, 0.6, 0.65])
    for i in range(frames):
        spin = 2 * math.pi * i / frames
        # stand the arrow up with the tip pointing down, spin it, tilt camera a little
        m = rot_x(math.radians(-10)) @ rot_y(spin) @ rot_z(math.pi)
        tris = [((m @ v.T).T, a) for v, a in model]
        size = cell * ss
        img = rasterize(tris, size, scale=size * 0.40, light=light)
        img = downsample(img, ss)
        img = add_outline(img, radius=1.4)
        r, c = divmod(i, cols)
        sheet[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell] = img
    save_tga(to_image(sheet), os.path.join(MEDIA, "Arrived.tga"))


# ---------------------------------------------------------------------------
# Classic block arrow: a thick slab with a shaft and a head, seen from behind
# and above. No outline, just a soft shadow, so it sits naturally in the game
# world.
# ---------------------------------------------------------------------------

# outline, counter-clockwise seen from above; the arrow points to +y
BLOCK_OUTLINE = [
    (0.00, 0.92),   # tip
    (-0.58, 0.12),  # head, left
    (-0.23, 0.12),  # shaft top, left
    (-0.23, -0.88), # shaft bottom, left
    (0.23, -0.88),  # shaft bottom, right
    (0.23, 0.12),   # shaft top, right
    (0.58, 0.12),   # head, right
]
BLOCK_TOP = 0.16
BLOCK_BOTTOM = -0.16


def block_triangles():
    top = [np.array([x, y, BLOCK_TOP]) for x, y in BLOCK_OUTLINE]
    bot = [np.array([x, y, BLOCK_BOTTOM]) for x, y in BLOCK_OUTLINE]
    tris = []

    def tri(a, b, c, want, albedo):
        n = np.cross(b - a, c - a)
        if np.dot(n, want) < 0:
            b, c = c, b
        tris.append((np.array([a, b, c]), albedo))

    up, down = np.array([0, 0, 1.0]), np.array([0, 0, -1.0])
    T, HL, SLT, SLB, SRB, SRT, HR = range(7)
    for (i, j, k) in [(T, HL, HR), (SLT, SLB, SRB), (SLT, SRB, SRT)]:
        tri(top[i], top[j], top[k], up, 1.0)
        tri(bot[i], bot[j], bot[k], down, 0.45)
    n = len(BLOCK_OUTLINE)
    for i in range(n):
        j = (i + 1) % n
        ax, ay = BLOCK_OUTLINE[i]
        bx, by = BLOCK_OUTLINE[j]
        outward = np.array([by - ay, -(bx - ax), 0.0])  # right-hand normal of a CCW edge
        tri(top[i], top[j], bot[j], outward, 0.78)
        tri(top[i], bot[j], bot[i], outward, 0.78)
    return tris


def add_soft_shadow(img, blur=2.2, strength=0.38, dy=2):
    """A faint blurred shadow under the arrow instead of a hard outline."""
    alpha = Image.fromarray((img[..., 3] * 255).astype(np.uint8), "L")
    sh = np.asarray(alpha.filter(ImageFilter.GaussianBlur(blur)), dtype=np.float64) / 255.0 * strength
    sh = np.roll(sh, dy, axis=0)
    a = img[..., 3:4]
    out = np.empty_like(img)
    base_a = sh[..., None]
    out_a = a + base_a * (1 - a)
    out[..., :3] = np.where(out_a > 0, (img[..., :3] * a) / np.maximum(out_a, 1e-9), 0)
    out[..., 3:4] = out_a
    return out


def render_block_frame(angle, w, h, tilt_deg=56.0, ss=4, scale=0.36):
    model = block_triangles()
    m = rot_x(-math.radians(tilt_deg)) @ rot_z(angle)
    tris = [((m @ v.T).T, a) for v, a in model]
    light = normalize([-0.35, 0.75, 0.55])
    img = rasterize(tris, w * ss, scale=w * ss * scale, light=light, height=h * ss,
                    ambient=0.42, diffuse=0.62, spec=0.18, shininess=10)
    img = downsample(img, ss)
    return add_soft_shadow(img)


def render_block_sheet():
    """108 frames, 9 columns x 12 rows of 112x84 in 1024x1024."""
    frames, cols, cw, ch, tex = 108, 9, 112, 84, 1024
    sheet = np.zeros((tex, tex, 4), dtype=np.float64)
    for i in range(frames):
        f = render_block_frame(2 * math.pi * i / frames, cw, ch)
        r, c = divmod(i, cols)
        sheet[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw] = f
    save_tga(to_image(sheet), os.path.join(MEDIA, "Arrow.tga"))


def render_block_arrived():
    """The block arrow standing on its tip and spinning (8x8 of 64px)."""
    frames, cols, cell, tex, ss = 64, 8, 64, 512, 4
    sheet = np.zeros((tex, tex, 4), dtype=np.float64)
    model = block_triangles()
    light = normalize([-0.4, 0.6, 0.7])
    for i in range(frames):
        spin = 2 * math.pi * i / frames
        m = rot_x(math.radians(-8)) @ rot_y(spin) @ rot_z(math.pi)
        tris = [((m @ v.T).T, a) for v, a in model]
        img = rasterize(tris, cell * ss, scale=cell * ss * 0.40, light=light, ambient=0.42, diffuse=0.62, spec=0.18)
        img = add_soft_shadow(downsample(img, ss), blur=1.6)
        r, c = divmod(i, cols)
        sheet[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell] = img
    save_tga(to_image(sheet), os.path.join(MEDIA, "Arrived.tga"))


# ---------------------------------------------------------------------------
# 2D art: map pin and icon (signed-distance shapes, supersampled)
# ---------------------------------------------------------------------------


def sdf_grid(size, ss):
    n = size * ss
    ys, xs = np.mgrid[0:n, 0:n]
    x = (xs + 0.5) / n * 2 - 1
    y = 1 - (ys + 0.5) / n * 2
    return x, y


def smooth_mask(d, px):
    return np.clip(0.5 - d / px, 0, 1)


def render_pin(size=64, ss=4):
    x, y = sdf_grid(size, ss)
    px = 2.0 / (size * ss) * ss  # one output pixel in sdf units
    # teardrop: circle centred at (0, 0.28) r=0.52 merged with a triangle to (0,-0.92)
    cx, cy, r = 0.0, 0.28, 0.50
    d_circle = np.hypot(x - cx, y - cy) - r
    # cone: distance to lines from tip to tangents (approx with max of two half-planes)
    tip_y = -0.90
    dist = cy - tip_y
    alpha = math.asin(r / dist)
    tangent_y = tip_y + dist * math.cos(alpha) ** 2
    d_cone = np.maximum(np.abs(x) * math.cos(alpha) - (y - tip_y) * math.sin(alpha), y - tangent_y)
    d = np.minimum(d_circle, d_cone)
    body = smooth_mask(d, px)
    rim = smooth_mask(d - 0.10, px)
    hole = smooth_mask(np.hypot(x - cx, y - cy) - 0.20, px)
    img = np.zeros(x.shape + (4,))
    # vertical shading for a little depth
    shade = 0.78 + 0.22 * np.clip((y + 1) / 2, 0, 1)
    img[..., 0] = shade
    img[..., 1] = shade
    img[..., 2] = shade
    # dark rim outside the body
    alpha = np.maximum(body, rim * 0.9)
    colour = np.where(body[..., None] > 0, img[..., :3], 0.05)
    colour = colour * body[..., None] + 0.05 * (1 - body[..., None])
    # dark hole in the middle
    colour = colour * (1 - hole[..., None]) + 0.08 * hole[..., None]
    out = np.zeros_like(img)
    out[..., :3] = colour
    out[..., 3] = alpha
    out = downsample(out, ss)
    save_tga(to_image(out), os.path.join(MEDIA, "Pin.tga"))


def gradient_arrow_icon(size, ss=4):
    """Icon: tinted 3D arrow on a dark round badge with a gold ring."""
    n = size * ss
    x, y = sdf_grid(size, ss)
    px = 2.0 / n
    r = np.hypot(x, y)
    img = np.zeros((n, n, 4))
    # badge background: dark teal radial gradient
    bg = np.clip(1 - r, 0, 1)
    img[..., 0] = 0.05 + 0.08 * bg
    img[..., 1] = 0.08 + 0.16 * bg
    img[..., 2] = 0.10 + 0.14 * bg
    badge = smooth_mask(r - 0.97, px)
    ring = smooth_mask(np.abs(r - 0.89) - 0.07, px)
    gold = np.stack([np.full_like(r, 0.95), np.full_like(r, 0.76), np.full_like(r, 0.25)], -1)
    ring_shade = (0.75 + 0.25 * np.clip(y, -1, 1))[..., None]
    img[..., :3] = img[..., :3] * (1 - ring[..., None]) + gold * ring_shade * ring[..., None]
    img[..., 3] = badge
    # arrow, rendered at higher res and tinted green -> gold
    arrow = render_block_frame(math.radians(-40), n, n * 3 // 4, tilt_deg=45, ss=1, scale=0.40)
    arrow_img = Image.fromarray((np.clip(arrow, 0, 1) * 255).astype(np.uint8), "RGBA")
    aw, ah = int(n * 0.95), int(n * 0.95 * 3 / 4)
    arrow_img = arrow_img.resize((aw, ah), Image.LANCZOS)
    a = np.asarray(arrow_img, dtype=np.float64) / 255.0
    px, py = (n - aw) // 2, (n - ah) // 2
    layer = np.zeros_like(img)
    layer[py:py + ah, px:px + aw] = a
    yy = np.linspace(1, 0, n)[:, None]
    tint = np.stack([0.30 + 0.70 * (1 - yy) + 0 * x, 0.82 + 0.18 * yy + 0 * x, 0.12 + 0.18 * yy + 0 * x], -1)
    tint = np.clip(tint, 0, 1)
    layer[..., :3] = layer[..., :3] * tint
    la = layer[..., 3:4]
    img[..., :3] = layer[..., :3] * la + img[..., :3] * (1 - la)
    img[..., 3:4] = np.maximum(img[..., 3:4], la)
    return downsample(img, ss)


def arrow_logo(size, ss=2, outline=False):
    """Logo and icon: the addon's own 3D block arrow on a transparent
    background, tinted gold at the tail to green at the tip (the colours it
    turns as you get closer), with a soft shadow."""
    n = size * ss
    arrow = render_block_frame(math.radians(-40), n, n, tilt_deg=45, ss=1, scale=0.50)
    a = np.array(arrow, dtype=np.float64)
    # gold (bottom-left, the tail) to green (top-right, the tip)
    ys, xs = np.mgrid[0:n, 0:n]
    t = np.clip(((xs / n) + (1 - ys / n)) / 2 * 1.3 - 0.15, 0, 1)[..., None]
    gold = np.array([1.00, 0.78, 0.10])
    green = np.array([0.35, 1.00, 0.25])
    tint = gold * (1 - t) + green * t
    a[..., :3] = np.clip(a[..., :3] * tint * 1.25, 0, 1)
    img = downsample(a, ss)
    # centre it, filling the square with a small margin
    alpha = img[..., 3] > 0.02
    rows, cols = np.where(alpha.any(1))[0], np.where(alpha.any(0))[0]
    crop = img[rows[0]:rows[-1] + 1, cols[0]:cols[-1] + 1]
    ch, cw = crop.shape[:2]
    fit = size * 0.88 / max(ch, cw)
    crop_img = to_image(crop).resize((max(1, round(cw * fit)), max(1, round(ch * fit))), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(crop_img, ((size - crop_img.width) // 2, (size - crop_img.height) // 2))
    img = np.asarray(out, dtype=np.float64) / 255.0
    if outline:
        img = add_outline(img, radius=1.2, strength=0.8, shadow=False)
    return img


def main():
    render_block_sheet()
    render_block_arrived()
    render_pin()
    icon = arrow_logo(64, ss=4, outline=True)
    save_tga(to_image(icon), os.path.join(MEDIA, "Icon.tga"))
    os.makedirs(DOCS, exist_ok=True)
    # CurseForge wants a square PNG of at least 400x400; 1024 stays sharp
    to_image(arrow_logo(1024, ss=2)).save(os.path.join(DOCS, "logo.png"))
    print("wrote docs/images/logo.png")


if __name__ == "__main__":
    main()
