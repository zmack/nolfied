#!/usr/bin/env python3
"""Generate all graphics for NOLFIED (SNES).

Outputs binary files into build/ that src/main.s .incbin's:
  bgtiles.bin   256 4bpp tiles: every combination of 4 field cells (2x2 per tile)
  font.bin      2bpp BG3 tiles: 64 ASCII glyphs + big title logo tiles
  title.map     BG3 tilemap fragment for the logo (W*H words)
  sprites.bin   4bpp OBJ tiles (128x64 sheet)
  objpal.bin    4 sprite palettes (16 colours each)
  picN.chr / picN.map / picN.pal   hidden stage pictures (240x192)
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else "build"
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(1987)


def bgr555(r, g, b):
    return ((b >> 3) << 10) | ((g >> 3) << 5) | (r >> 3)


def pal_bytes(cols):
    out = bytearray()
    for c in cols:
        v = bgr555(*c)
        out += bytes((v & 0xFF, v >> 8))
    return out


def tile4(px):
    """px: 8x8 array of indices 0-15 -> 32 bytes SNES 4bpp."""
    b = bytearray(32)
    for y in range(8):
        for x in range(8):
            v = int(px[y][x])
            bit = 7 - x
            if v & 1: b[y * 2] |= 1 << bit
            if v & 2: b[y * 2 + 1] |= 1 << bit
            if v & 4: b[16 + y * 2] |= 1 << bit
            if v & 8: b[16 + y * 2 + 1] |= 1 << bit
    return bytes(b)


def tile2(px):
    b = bytearray(16)
    for y in range(8):
        for x in range(8):
            v = int(px[y][x])
            bit = 7 - x
            if v & 1: b[y * 2] |= 1 << bit
            if v & 2: b[y * 2 + 1] |= 1 << bit
    return bytes(b)


def write(name, data):
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(data)


# ---------------------------------------------------------------------------
# BG1 field tiles. Cell states: 0 unclaimed cover, 1 claimed (transparent),
# 2 edge line, 3 trail. Tile n = q0 | q1<<2 | q2<<4 | q3<<6 with quadrants
# TL, TR, BL, BR (each a 4x4 pixel cell).
# Palette (CGRAM 32..): 1 cover dark, 2 cover dot, 3 edge, 4 trail, 5 edge shade
def cell_pixels(state, x, y):
    if state == 0:
        return 2 if (x == 1 and y == 1) else 1
    if state == 1:
        return 0
    if state == 2:
        return 5 if (x == 3 or y == 3) else 3
    return 4


bg = bytearray()
for n in range(256):
    q = [(n >> (2 * i)) & 3 for i in range(4)]
    px = [[0] * 8 for _ in range(8)]
    for y in range(8):
        for x in range(8):
            qi = (x >> 2) + 2 * (y >> 2)
            px[y][x] = cell_pixels(q[qi], x & 3, y & 3)
    bg += tile4(px)
write("bgtiles.bin", bg)

# ---------------------------------------------------------------------------
# Font (5x7 glyphs with drop shadow) for ASCII 32..95
F = {
    '0': "01110 10001 10011 10101 11001 10001 01110",
    '1': "00100 01100 00100 00100 00100 00100 01110",
    '2': "01110 10001 00001 00010 00100 01000 11111",
    '3': "11111 00010 00100 00010 00001 10001 01110",
    '4': "00010 00110 01010 10010 11111 00010 00010",
    '5': "11111 10000 11110 00001 00001 10001 01110",
    '6': "00110 01000 10000 11110 10001 10001 01110",
    '7': "11111 00001 00010 00100 01000 01000 01000",
    '8': "01110 10001 10001 01110 10001 10001 01110",
    '9': "01110 10001 10001 01111 00001 00010 01100",
    'A': "01110 10001 10001 11111 10001 10001 10001",
    'B': "11110 10001 10001 11110 10001 10001 11110",
    'C': "01110 10001 10000 10000 10000 10001 01110",
    'D': "11100 10010 10001 10001 10001 10010 11100",
    'E': "11111 10000 10000 11110 10000 10000 11111",
    'F': "11111 10000 10000 11110 10000 10000 10000",
    'G': "01110 10001 10000 10111 10001 10001 01111",
    'H': "10001 10001 10001 11111 10001 10001 10001",
    'I': "01110 00100 00100 00100 00100 00100 01110",
    'J': "00111 00010 00010 00010 00010 10010 01100",
    'K': "10001 10010 10100 11000 10100 10010 10001",
    'L': "10000 10000 10000 10000 10000 10000 11111",
    'M': "10001 11011 10101 10101 10001 10001 10001",
    'N': "10001 10001 11001 10101 10011 10001 10001",
    'O': "01110 10001 10001 10001 10001 10001 01110",
    'P': "11110 10001 10001 11110 10000 10000 10000",
    'Q': "01110 10001 10001 10001 10101 10010 01101",
    'R': "11110 10001 10001 11110 10100 10010 10001",
    'S': "01111 10000 10000 01110 00001 00001 11110",
    'T': "11111 00100 00100 00100 00100 00100 00100",
    'U': "10001 10001 10001 10001 10001 10001 01110",
    'V': "10001 10001 10001 10001 10001 01010 00100",
    'W': "10001 10001 10001 10101 10101 10101 01010",
    'X': "10001 10001 01010 00100 01010 10001 10001",
    'Y': "10001 10001 10001 01010 00100 00100 00100",
    'Z': "11111 00001 00010 00100 01000 10000 11111",
    '%': "11000 11001 00010 00100 01000 10011 00011",
    '!': "00100 00100 00100 00100 00100 00000 00100",
    '.': "00000 00000 00000 00000 00000 01100 01100",
    ',': "00000 00000 00000 00000 01100 00100 01000",
    '-': "00000 00000 00000 11111 00000 00000 00000",
    ':': "00000 01100 01100 00000 01100 01100 00000",
    '/': "00000 00001 00010 00100 01000 10000 00000",
    '?': "01110 10001 00001 00010 00100 00000 00100",
    "'": "00100 00100 01000 00000 00000 00000 00000",
    '(': "00010 00100 01000 01000 01000 00100 00010",
    ')': "01000 00100 00010 00010 00010 00100 01000",
    '*': "00000 01010 11111 11111 01110 00100 00000",  # heart (lives icon)
    '=': "00000 00000 11111 00000 11111 00000 00000",
    '+': "00000 00100 00100 11111 00100 00100 00000",
    '>': "01000 00100 00010 00001 00010 00100 01000",
    '<': "00010 00100 01000 10000 01000 00100 00010",
}

font = bytearray()
for code in range(32, 96):
    ch = chr(code)
    px = [[0] * 8 for _ in range(8)]
    if ch in F:
        rows = F[ch].split()
        for y, row in enumerate(rows):
            for x, c in enumerate(row):
                if c == '1':
                    if px[y + 1][x + 2] == 0:
                        px[y + 1][x + 2] = 2
        for y, row in enumerate(rows):
            for x, c in enumerate(row):
                if c == '1':
                    px[y][x + 1] = 1
    font += tile2(px)

# Big logo "NOLFIED": glyphs scaled 3x, gradient + outline. 2bpp colours:
# 1 = lower body, 2 = outline, 3 = upper highlight
word = "NOLFIED"
S = 3
LW, LH = 18 * 8, 3 * 8
logo = np.zeros((LH, LW), dtype=np.uint8)
body = np.zeros((LH, LW), dtype=bool)
ox = (LW - (len(word) * 6 * S - S)) // 2
for i, ch in enumerate(word):
    rows = F[ch].split()
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            if c == '1':
                X = ox + (i * 6 + x) * S
                Y = 1 + y * S
                body[Y:Y + S, X:X + S] = True
outline = np.zeros_like(body)
for dy in (-1, 0, 1):
    for dx in (-1, 0, 1):
        outline |= np.roll(np.roll(body, dy, 0), dx, 1)
logo[outline] = 2
for y in range(LH):
    logo[y][body[y]] = 3 if y < 11 else 1
title_map = bytearray()
for ty in range(3):
    for tx in range(18):
        idx = 64 + ty * 18 + tx
        font += tile2(logo[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8])
        v = idx | (2 << 10) | 0x2000  # palette 2, priority
        title_map += bytes((v & 0xFF, v >> 8))
write("font.bin", font)
write("title.map", title_map)

# ---------------------------------------------------------------------------
# Sprites: 128x64 sheet, 4bpp.
sheet = Image.new("P", (128, 64), 0)
d = ImageDraw.Draw(sheet)


def put(img, x0, y0):
    sheet.paste(img, (x0, y0))


def ship(frame):
    im = Image.new("P", (16, 16), 0)
    g = ImageDraw.Draw(im)
    # four fins
    fin = 6 if frame == 0 else 3
    g.polygon([(7.5, 0), (10, 5), (5, 5)], fill=4)
    g.polygon([(7.5, 15), (10, 10), (5, 10)], fill=4)
    g.polygon([(0, 7.5), (5, 5), (5, 10)], fill=4)
    g.polygon([(15, 7.5), (10, 5), (10, 10)], fill=4)
    g.ellipse([3, 3, 12, 12], fill=1)
    g.ellipse([4, 4, 11, 11], fill=2)
    g.ellipse([5, 5, 9, 9], fill=3)
    g.ellipse([6, 6, 8, 8], fill=fin)
    g.point([(7, 0), (0, 7), (15, 8), (8, 15)], fill=5)
    return im


def boss(frame):
    im = Image.new("P", (32, 32), 0)
    g = ImageDraw.Draw(im)
    cx = cy = 15.5
    off = 0 if frame == 0 else math.pi / 8
    for k in range(8):
        a = off + k * math.pi / 4
        tip = (cx + 15.5 * math.cos(a), cy + 15.5 * math.sin(a))
        l = (cx + 9 * math.cos(a - 0.35), cy + 9 * math.sin(a - 0.35))
        r = (cx + 9 * math.cos(a + 0.35), cy + 9 * math.sin(a + 0.35))
        g.polygon([tip, l, r], fill=8, outline=1)
    g.ellipse([5, 5, 26, 26], fill=1)
    g.ellipse([6, 6, 25, 25], fill=2)
    g.ellipse([7, 7, 21, 21], fill=3)
    g.ellipse([9, 8, 15, 13], fill=4)
    # eye
    g.ellipse([10, 11, 21, 20], fill=5, outline=1)
    px = 15 if frame == 0 else 16
    g.ellipse([px - 3, 12, px + 3, 19], fill=6)
    g.ellipse([px - 1, 14, px + 1, 17], fill=1)
    g.point([(px - 2, 13)], fill=5)
    return im


def minion(frame):
    im = Image.new("P", (16, 16), 0)
    g = ImageDraw.Draw(im)
    c = 7.5
    off = 0 if frame == 0 else math.pi / 4
    pts = []
    for k in range(8):
        a = off + k * math.pi / 4
        rr = 7.5 if k % 2 == 0 else 3
        pts.append((c + rr * math.cos(a), c + rr * math.sin(a)))
    g.polygon(pts, fill=2, outline=1)
    g.ellipse([5, 5, 10, 10], fill=3)
    g.ellipse([6, 6, 8, 8], fill=4)
    return im


def item():
    im = Image.new("P", (16, 16), 0)
    g = ImageDraw.Draw(im)
    g.rounded_rectangle([1, 2, 14, 13], radius=3, fill=1)
    g.rounded_rectangle([2, 3, 13, 12], radius=2, fill=2)
    g.rectangle([3, 4, 12, 6], fill=3)
    q = ["0110", "1001", "0010", "0100", "0000", "0100"]
    for y, row in enumerate(q):
        for x, c in enumerate(row):
            if c == '1':
                im.putpixel((6 + x, 5 + y), 4)
    return im


def boom(frame):
    im = Image.new("P", (16, 16), 0)
    g = ImageDraw.Draw(im)
    if frame == 0:
        g.ellipse([3, 3, 12, 12], fill=5)
        g.ellipse([5, 5, 10, 10], fill=6)
    else:
        for k in range(8):
            a = k * math.pi / 4
            x, y = 7.5 + 6 * math.cos(a), 7.5 + 6 * math.sin(a)
            g.ellipse([x - 1.5, y - 1.5, x + 1.5, y + 1.5], fill=7)
        g.ellipse([5, 5, 10, 10], fill=5)
    return im


put(ship(0), 0, 0)
put(ship(1), 16, 0)
put(minion(0), 32, 0)
put(minion(1), 48, 0)
put(item(), 64, 0)
put(boom(0), 80, 0)
put(boom(1), 96, 0)
put(boss(0), 0, 16)
put(boss(1), 32, 16)
arr = np.array(sheet)
spr = bytearray()
for ty in range(8):
    for tx in range(16):
        spr += tile4(arr[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8])
write("sprites.bin", spr)

K = (0, 0, 0)
objpal = bytearray()
# pal 0: player
objpal += pal_bytes([K, (16, 24, 64), (96, 200, 255), (232, 248, 255), (40, 120, 220),
                     (255, 255, 255), (255, 200, 40)] + [K] * 9)
# pal 1: boss
objpal += pal_bytes([K, (24, 0, 32), (96, 24, 120), (160, 56, 184), (232, 150, 240),
                     (255, 255, 240), (230, 30, 40), K, (255, 90, 200)] + [K] * 7)
# pal 2: minions / explosions
objpal += pal_bytes([K, (20, 40, 0), (120, 220, 40), (240, 255, 120), (255, 255, 255),
                     (255, 240, 160), (255, 140, 20), (255, 60, 0)] + [K] * 8)
# pal 3: item capsule
objpal += pal_bytes([K, (60, 30, 0), (240, 170, 30), (255, 230, 130), (80, 20, 0)] + [K] * 11)
write("objpal.bin", objpal)

# ---------------------------------------------------------------------------
# Stage pictures 240x192, procedurally generated.
W, H = 240, 192
yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)


def fbm(octaves=5, base=6, seed=0):
    r = np.random.default_rng(seed)
    acc = np.zeros((H, W))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        n = base * (2 ** o)
        g = r.random((n + 1, n + 1))
        im = Image.fromarray((g * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
        acc += amp * (np.asarray(im, dtype=np.float64) / 255.0)
        tot += amp
        amp *= 0.5
    return acc / tot


def stars(img, n, seed):
    r = np.random.default_rng(seed)
    for _ in range(n):
        x, y = r.integers(0, W), r.integers(0, H)
        b = r.integers(120, 256)
        img[y, x] = np.maximum(img[y, x], [b, b, min(255, b + 30)])
    return img


def ramp(t, stops):
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    pos = [s[0] for s in stops]
    for ch in range(3):
        out[..., ch] = np.interp(t, pos, [s[1][ch] for s in stops])
    return out


def pic_planet():
    img = np.zeros((H, W, 3))
    neb = fbm(5, 4, 11)
    img += ramp(neb, [(0, (0, 0, 10)), (0.55, (10, 10, 40)), (1, (60, 20, 80))])
    img = stars(img, 260, 3)
    cx, cy, r = 128, 98, 56
    dx, dy = (xx - cx) / r, (yy - cy) / r
    d2 = dx * dx + dy * dy
    inside = d2 <= 1
    nz = np.sqrt(np.clip(1 - d2, 0, 1))
    light = np.clip(-0.55 * dx - 0.6 * dy + 0.6 * nz, 0, 1)
    bands = 0.5 + 0.5 * np.sin(dy * 9 + 2 * fbm(3, 3, 5))
    base = ramp(bands, [(0, (180, 90, 40)), (0.5, (230, 170, 90)), (1, (250, 220, 160))])
    shade = base * (0.15 + 0.85 * light[..., None])
    img[inside] = shade[inside]
    # ring
    ang = -0.35
    rx = (xx - cx) * math.cos(ang) - (yy - cy) * math.sin(ang)
    ry = (xx - cx) * math.sin(ang) + (yy - cy) * math.cos(ang)
    rr = np.sqrt((rx / 1.0) ** 2 + (ry / 0.28) ** 2)
    ring = (rr > r * 1.25) & (rr < r * 1.75) & (np.abs(rr - r * 1.5) > 2.5)
    front = ry > 0
    show = ring & (front | ~inside)
    rc = ramp((rr - r * 1.25) / (r * 0.5), [(0, (200, 180, 150)), (0.5, (140, 110, 90)), (1, (220, 200, 170))])
    img[show] = rc[show] * 0.9
    # small moon
    m = (xx - 40) ** 2 + (yy - 40) ** 2 < 11 ** 2
    ml = np.clip(1 - ((xx - 36) ** 2 + (yy - 36) ** 2) / 300, 0.2, 1)
    img[m] = (np.array([170, 190, 220]) * ml[..., None])[m]
    return img


def pic_nebula():
    n1 = fbm(6, 3, 21)
    n2 = fbm(5, 5, 22)
    t = np.clip((n1 - 0.3) * 2.2, 0, 1)
    img = ramp(t, [(0, (2, 0, 12)), (0.35, (40, 10, 90)), (0.6, (180, 40, 140)),
                   (0.8, (255, 140, 120)), (1, (255, 240, 200))])
    teal = np.clip((n2 - 0.55) * 4, 0, 1)[..., None]
    img = img * (1 - teal * 0.6) + teal * 0.6 * np.array([30, 200, 200])
    img = stars(img, 320, 7)
    # bright core star
    d = np.sqrt((xx - 150) ** 2 + (yy - 85) ** 2)
    glow = np.exp(-d / 14)[..., None]
    img = img * (1 - glow) + glow * 255
    return img


def pic_sunset():
    t = yy / H
    img = ramp(t, [(0, (30, 10, 70)), (0.35, (150, 40, 120)), (0.55, (255, 120, 60)), (0.62, (255, 200, 100))])
    # sun with stripes
    d = np.sqrt((xx - 120) ** 2 + (yy - 100) ** 2)
    sun = (d < 44) & ~((yy > 82) & (((yy - 82) // 5) % 2 == 1))
    img[sun] = ramp(((yy - 56) / 88)[sun], [(0, (255, 255, 160)), (1, (255, 90, 60))])
    horizon = 118
    for layer, (seed, height, col) in enumerate([(31, 40, (90, 30, 90)), (32, 26, (50, 15, 60)), (33, 14, (20, 5, 30))]):
        ridge = np.random.default_rng(seed).random(W // 8 + 2)
        prof = np.interp(np.arange(W), np.arange(len(ridge)) * 8, ridge)
        prof2 = np.interp(np.arange(W), np.arange(0, W + 40, 40), np.random.default_rng(seed + 9).random(W // 40 + 2)[: len(range(0, W + 40, 40))])
        top = horizon - (height * (0.4 * prof + 0.6 * prof2)) + layer * 6
        mask = yy >= top[None, :]
        img[mask & (yy < horizon + 4)] = col
    # water: reflection with ripples
    wy = yy > horizon + 3
    src_y = np.clip(2 * (horizon + 3) - yy, 0, H - 1).astype(int)
    rip = (np.sin(yy * 1.3) * 3).astype(int)
    src_x = np.clip(xx.astype(int) + rip, 0, W - 1)
    refl = img[src_y, src_x] * 0.55 + np.array([0, 10, 40])
    img[wy] = refl[wy]
    return img


def pic_crystal():
    dx, dy = xx - 120, yy - 96
    r = np.sqrt(dx * dx + dy * dy)
    a = np.arctan2(dy, dx)
    petal = np.abs(np.cos(a * 6)) * 60 + 20
    p2 = np.abs(np.cos(a * 6 + math.pi / 2)) * 40 + 10
    img = ramp(fbm(4, 4, 41) * 0.6, [(0, (0, 10, 30)), (1, (10, 60, 90))])
    l2 = r < p2 + 30
    img[l2] = ramp((r / (p2 + 30))[l2], [(0, (255, 255, 255)), (0.4, (120, 240, 255)), (1, (20, 120, 200))])
    l1 = (r < petal) & ~l2
    img[l1] = ramp((r / petal)[l1], [(0, (255, 255, 200)), (0.5, (255, 120, 200)), (1, (120, 20, 120))])
    rings = (np.abs(r - 85) < 2) | (np.abs(r - 92) < 1)
    img[rings] = (255, 210, 120)
    spokes = (np.abs(np.sin(a * 12)) < 0.06) & (r > 95)
    img[spokes] = (60, 160, 220)
    img = stars(img, 120, 9)
    return img


def make_pic(idx, img):
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")
    q = im.quantize(colors=15, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
    pal = q.getpalette()[:45]
    a = np.array(q, dtype=np.uint8) + 1  # indices 1..15 (0 = transparent)
    tiles = [bytes(32)]  # tile 0 blank
    lut = {tiles[0]: 0}
    tmap = []
    for ty in range(24):
        for tx in range(30):
            t = tile4(a[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8])
            if t not in lut:
                lut[t] = len(tiles)
                tiles.append(t)
            tmap.append(lut[t])
    assert len(tiles) <= 1024
    full = bytearray()
    for row in range(32):
        for col in range(32):
            fy, fx = row - 3, col - 1
            if 0 <= fy < 24 and 0 <= fx < 30:
                v = tmap[fy * 30 + fx] | (3 << 10)
            else:
                v = 0
            full += bytes((v & 0xFF, v >> 8))
    cols = [(0, 0, 0)] + [tuple(pal[i * 3:i * 3 + 3]) for i in range(15)]
    write(f"pic{idx}.chr", b"".join(tiles))
    write(f"pic{idx}.map", full)
    write(f"pic{idx}.pal", pal_bytes(cols))
    im_preview = Image.fromarray(np.array(q.convert("RGB")))
    im_preview.save(os.path.join(OUT, f"pic{idx}_preview.png"))
    print(f"pic{idx}: {len(tiles)} tiles")


for i, fn in enumerate([pic_planet, pic_nebula, pic_sunset, pic_crystal]):
    make_pic(i, fn())
Image.fromarray((arr * 30).astype(np.uint8)).resize((512, 256), Image.NEAREST).save(os.path.join(OUT, "sprites_preview.png"))
print("assets ok")
