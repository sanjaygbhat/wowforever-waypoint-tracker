#!/usr/bin/env python3
"""Render the README images from the addon's real arrow textures.

    python3 tools/render_readme.py

Writes docs/images/banner.png, arrow-demo.gif and colours.png.
Run tools/render_art.py first (it makes the textures these are built from).
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "WaypointTracker", "Media")
OUT = os.path.join(ROOT, "docs", "images")

SERIF_BOLD = "/usr/share/fonts/truetype/freefont/FreeSerifBold.ttf"
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
SANS_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

GOLD = (255, 209, 0)
GREEN = (0.20, 1.00, 0.30)
YELLOW = (1.00, 0.85, 0.10)
RED = (1.00, 0.22, 0.15)

SHEET = Image.open(os.path.join(MEDIA, "Arrow.tga")).convert("RGBA")
ARRIVED = Image.open(os.path.join(MEDIA, "Arrived.tga")).convert("RGBA")
LOGO = Image.open(os.path.join(OUT, "logo.png")).convert("RGBA")


ARROW_GOLD = (1.00, 0.80, 0.10)


def gradient(p):
    """Same as Arrow.DistanceColour: 0 (arrived) green -> 1 (far) gold."""
    p = max(0.0, min(1.0, p))
    return tuple(GREEN[i] + (ARROW_GOLD[i] - GREEN[i]) * p for i in range(3))


FRAMES = 108  # Arrow.tga: 9 columns x 12 rows of 112x84


def arrow_frame(index, colour, size):
    """size = output width; frames are 4:3."""
    index %= FRAMES
    col, row = index % 9, index // 9
    cell = SHEET.crop((col * 112, row * 84, col * 112 + 112, row * 84 + 84))
    arr = np.asarray(cell).astype(np.float64)
    arr[..., :3] *= np.array(colour)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    return img.resize((size, size * 3 // 4), Image.LANCZOS)


def arrived_frame(index, colour, size):
    col, row = index % 8, index // 8
    cell = ARRIVED.crop((col * 64, row * 64, col * 64 + 64, row * 64 + 64))
    arr = np.asarray(cell).astype(np.float64)
    arr[..., :3] *= np.array(colour)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    return img.resize((size, size), Image.LANCZOS)


def backdrop(w, h, top=(18, 34, 44), bottom=(6, 10, 14), seed=7):
    """Dusky sky with a soft glow and a sprinkle of stars."""
    y = np.linspace(0, 1, h)[:, None]
    base = np.array(top)[None, None, :] * (1 - y[..., None]) + np.array(bottom)[None, None, :] * y[..., None]
    base = np.repeat(base, w, axis=1)
    xx, yy = np.meshgrid(np.linspace(-1, 1, w), np.linspace(-1, 1, h))
    glow = np.exp(-((xx - 0.45) ** 2 * 2.2 + (yy + 0.1) ** 2 * 3.0))
    base += glow[..., None] * np.array([30, 48, 40])
    rng = np.random.default_rng(seed)
    img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    d = ImageDraw.Draw(img)
    for _ in range(int(w * h / 2600)):
        sx, sy = rng.integers(0, w), rng.integers(0, int(h * 0.75))
        b = int(rng.integers(90, 200))
        r = rng.choice([0, 0, 0, 1])
        d.ellipse((sx - r, sy - r, sx + r, sy + r), fill=(b, b, min(255, b + 20), 255))
    return img


def text_shadow(draw, xy, text, font, fill, shadow=(0, 0, 0, 200), offset=2, anchor="la"):
    x, y = xy
    draw.text((x + offset, y + offset), text, font=font, fill=shadow, anchor=anchor)
    draw.text((x, y), text, font=font, fill=fill, anchor=anchor)


def dotted_path(draw, points, colour, step=14, r=2.4):
    """Dashes along a polyline — the path the arrow leads you down."""
    acc = 0.0
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        seg = math.hypot(x1 - x0, y1 - y0)
        t = acc
        while t < seg:
            px, py = x0 + (x1 - x0) * t / seg, y0 + (y1 - y0) * t / seg
            draw.ellipse((px - r, py - r, px + r, py + r), fill=colour)
            t += step
        acc = t - seg


def banner():
    w, h = 1280, 400
    img = backdrop(w, h)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # the journey: dotted path from the arrows to a pin
    path = [(700, 330), (820, 300), (900, 250), (1010, 235), (1100, 175), (1150, 128)]
    dotted_path(d, path, (255, 209, 0, 150))
    img.alpha_composite(layer)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    pin = Image.open(os.path.join(MEDIA, "Pin.tga")).convert("RGBA").resize((64, 64), Image.LANCZOS)
    pa = np.asarray(pin).astype(np.float64)
    pa[..., :3] *= np.array([1.0, 0.82, 0.0])
    pin = Image.fromarray(np.clip(pa, 0, 255).astype(np.uint8), "RGBA")
    glow = Image.new("RGBA", (160, 160), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((40, 40, 120, 120), fill=(255, 209, 0, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(18))
    img.alpha_composite(glow, (1150 - 80, 128 - 60))
    img.alpha_composite(pin, (1150 - 32, 128 - 62))

    # three arrows, red -> yellow -> green, getting closer
    for i, (x, y, p, idx, size) in enumerate([(630, 262, 1.0, 95, 130), (810, 196, 0.5, 97, 142), (985, 132, 0.02, 99, 156)]):
        a = arrow_frame(idx, gradient(p), size)
        img.alpha_composite(a, (x, y - size // 2 + 40))

    # logo + title
    logo = LOGO.resize((150, 150), Image.LANCZOS)
    img.alpha_composite(logo, (60, 95))
    title = ImageFont.truetype(SERIF_BOLD, 76)
    sub = ImageFont.truetype(SANS, 25)
    small = ImageFont.truetype(SANS_BOLD, 17)
    text_shadow(d, (236, 112), "Waypoint Tracker", title, GOLD, offset=3)
    text_shadow(d, (240, 205), "Set a waypoint. Follow the arrow. That's it.", sub, (235, 235, 235, 255))
    tag = "  FOR WORLD OF WARCRAFT: FOREVER  "
    tw = d.textlength(tag, font=small)
    d.rounded_rectangle((240, 256, 240 + tw, 284), 6, fill=(255, 209, 0, 36), outline=(255, 209, 0, 140))
    d.text((240, 260), tag, font=small, fill=GOLD)
    img.alpha_composite(layer)

    # soft vignette
    vig = Image.new("L", (w, h), 0)
    ImageDraw.Draw(vig).rectangle((0, 0, w, h), fill=0)
    mask = np.zeros((h, w))
    xx, yy = np.meshgrid(np.linspace(-1, 1, w), np.linspace(-1, 1, h))
    mask = np.clip((xx ** 2 * 0.35 + yy ** 2 * 0.9) - 0.45, 0, 1) * 150
    shade = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    shade.putalpha(Image.fromarray(mask.astype(np.uint8), "L"))
    img.alpha_composite(shade)
    img.convert("RGB").save(os.path.join(OUT, "banner.png"), optimize=True)
    print("wrote docs/images/banner.png")


def demo_gif():
    """The arrow swings round as you turn, then goes red -> yellow -> green
    as you walk in, and finishes with the 'You have arrived!' spin."""
    w, h = 480, 270
    bg = backdrop(w, h, top=(22, 40, 36), bottom=(8, 14, 12), seed=3)
    # a faint ground plane
    ground = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(ground)
    for i in range(1, 8):
        y = 150 + i * i * 1.9
        gd.line((0, y, w, y), fill=(160, 220, 180, 6 + i * 3))
    bg.alpha_composite(ground)
    title_font = ImageFont.truetype(SANS_BOLD, 17)
    dist_font = ImageFont.truetype(SANS, 16)
    cap_font = ImageFont.truetype(SANS, 12)

    frames, durations = [], []
    start = 420.0
    total = 96
    for f in range(total):
        img = bg.copy()
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        t = f / (total - 1)
        cx, cy = w // 2, 108
        if f < 24:
            # player turning to face the waypoint
            angle = 140 * (1 - f / 23) ** 2
            dist = start
            caption = "Turn until the arrow points up..."
        elif f < 80:
            k = (f - 24) / 55
            angle = 12 * math.sin(k * math.pi * 3) * (1 - k)
            dist = start * (1 - k) ** 1.4 + 0.0
            caption = "...and walk. Gold is far, green is close."
        else:
            angle, dist = 0, 0
            caption = "Arrived! The waypoint clears itself."
        if f < 80:
            p = max(0.0, min(1.0, dist / start))
            idx = int(round(((angle % 360) / 360) * FRAMES)) % FRAMES
            a = arrow_frame(idx, gradient(p), 120)
            img.alpha_composite(a, (cx - 60, cy - 45))
            text_shadow(d, (cx, cy + 58), "Goldshire", title_font, GOLD, anchor="ma")
            text_shadow(d, (cx, cy + 80), f"{int(round(dist))} yds", dist_font, (255, 255, 255, 255), anchor="ma")
        else:
            k = f - 80
            a = arrived_frame((k * 4) % 64, GREEN, 96)
            bob = int(math.sin(k * 0.8) * 4)
            img.alpha_composite(a, (cx - 48, cy - 48 + bob))
            text_shadow(d, (cx, cy + 58), "Goldshire", title_font, GOLD, anchor="ma")
            text_shadow(d, (cx, cy + 80), "You have arrived!", dist_font, (120, 255, 140, 255), anchor="ma")
        d.rounded_rectangle((12, h - 34, w - 12, h - 10), 6, fill=(0, 0, 0, 120))
        d.text((w // 2, h - 22), caption, font=cap_font, fill=(230, 230, 230, 255), anchor="mm")
        img.alpha_composite(layer)
        frames.append(img.convert("RGB").convert("P", palette=Image.ADAPTIVE, colors=128))
        durations.append(60)
    durations[23] = 500
    durations[79] = 400
    durations[-1] = 1400
    frames[0].save(
        os.path.join(OUT, "arrow-demo.gif"),
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        optimize=True,
        disposal=1,
    )
    print("wrote docs/images/arrow-demo.gif", os.path.getsize(os.path.join(OUT, "arrow-demo.gif")) // 1024, "KB")


def colours():
    w, h = 900, 230
    img = backdrop(w, h, top=(20, 30, 36), bottom=(10, 14, 18), seed=11)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    label = ImageFont.truetype(SANS_BOLD, 22)
    sub = ImageFont.truetype(SANS, 16)
    items = [
        (1.0, "Far away", "just set it"),
        (0.5, "Getting closer", "keep going"),
        (0.05, "Almost there", "look around!"),
    ]
    for i, (p, name, hint) in enumerate(items):
        cx = 150 + i * 300
        a = arrow_frame(0, gradient(p), 130)
        img.alpha_composite(a, (cx - 65, 30))
        c = tuple(int(v * 255) for v in gradient(p)) + (255,)
        text_shadow(d, (cx, 150), name, label, c, anchor="ma")
        d.text((cx, 182), hint, font=sub, fill=(200, 200, 200, 255), anchor="ma")
        if i < 2:
            dotted_path(d, [(cx + 85, 78), (cx + 215, 78)], (255, 255, 255, 90), step=12, r=2)
    img.alpha_composite(layer)
    img.convert("RGB").save(os.path.join(OUT, "colours.png"), optimize=True)
    print("wrote docs/images/colours.png")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    banner()
    demo_gif()
    colours()
