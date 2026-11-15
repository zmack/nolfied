#!/usr/bin/env python3
"""Perk-card icon generator.  Usage: python3 tools/gen_icons.py <outdir>

Writes icons.bin (256 4bpp tiles, 128x128 sheet of 16 32x32 icons),
iconpal.bin (16-colour BGR555 palette), minis.bin (16 2bpp 8x8 HUD glyphs),
icons_preview.png (4x) and minis_preview.png (8x).
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else "build"
os.makedirs(OUT, exist_ok=True)


def bgr555(r, g, b):
    return ((b >> 3) << 10) | ((g >> 3) << 5) | (r >> 3)


def pal_bytes(cols):
    out = bytearray()
    for c in cols:
        v = bgr555(*c)
        out += bytes((v & 0xFF, v >> 8))
    return out


def tile4(px):
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


# ---------------------------------------------------------------- palette
PAL = [
    (0, 0, 0),         # 0 transparent
    (24, 16, 40),      # 1 outline
    (255, 255, 255),   # 2 white
    (192, 200, 216),   # 3 light grey
    (96, 104, 130),    # 4 dark grey
    (224, 40, 52),     # 5 red
    (255, 144, 32),    # 6 orange
    (255, 232, 72),    # 7 yellow
    (150, 88, 32),     # 8 brown
    (64, 200, 72),     # 9 green
    (20, 100, 56),     # 10 dark green
    (88, 224, 248),    # 11 cyan
    (48, 96, 224),     # 12 blue
    (140, 72, 200),    # 13 purple
    (255, 136, 192),   # 14 pink
    (255, 208, 168),   # 15 peach
]
K, W, LG, DG, R, O, Y, BR, G, DGR, C, B, P, PK, PE = range(1, 16)

# ---------------------------------------------------------------- helpers


def canvas():
    im = Image.new("P", (32, 32), 0)
    return im, ImageDraw.Draw(im)


def outline(im):
    a = np.array(im, dtype=np.uint8)
    m = a > 0
    d = np.zeros_like(m)
    p = np.pad(m, 1)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx or dy:
                d |= p[1 + dy:33 + dy, 1 + dx:33 + dx]
    a[(~m) & d] = K
    return Image.fromarray(a, "P")


def pts(draw, lst, fill):
    draw.polygon([(float(x), float(y)) for x, y in lst], fill=fill)


def disc(d, cx, cy, r, fill):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def sparkle(d, cx, cy, r=3, col=W):
    d.line([(cx - r, cy), (cx + r, cy)], fill=col)
    d.line([(cx, cy - r), (cx, cy + r)], fill=col)
    d.point((cx, cy), fill=W)


def heart(d, cx, cy, s, fill):
    r = s * 0.28
    disc(d, cx - s * 0.25, cy - s * 0.15, r, fill)
    disc(d, cx + s * 0.25, cy - s * 0.15, r, fill)
    pts(d, [(cx - s * 0.52, cy - s * 0.05), (cx + s * 0.52, cy - s * 0.05),
            (cx, cy + s * 0.5)], fill)


# ---------------------------------------------------------------- icons
def i_greed():
    im, d = canvas()
    for ty in (20, 13, 6):
        d.rectangle([5, ty + 4, 26, ty + 9], fill=O)
        d.rectangle([5, ty + 8, 26, ty + 9], fill=BR)
        d.ellipse([5, ty + 5, 26, ty + 10], fill=BR)
        d.ellipse([5, ty, 26, ty + 8], fill=Y)
        d.ellipse([8, ty + 2, 23, ty + 6], outline=O)
        d.line([(12, ty + 4), (19, ty + 4)], fill=O)
        d.line([(9, ty + 2), (12, ty + 1)], fill=W)
    d.line([(8, 12), (8, 15)], fill=O)
    return outline(im)


def i_chain():
    im, d = canvas()
    # link B (vertical) drawn first, link A (horizontal) over it
    def link(box, col_o, col_i):
        d.rounded_rectangle(box, radius=6, outline=col_o, width=5)
        b2 = [box[0] + 1, box[1] + 1, box[2] - 1, box[3] - 1]
        d.rounded_rectangle(b2, radius=5, outline=col_i, width=3)
    link([15, 8, 29, 30], DG, LG)
    link([2, 2, 22, 16], DG, LG)
    # re-weave: B's left bar passes over A's bottom bar
    d.rectangle([15, 13, 19, 16], fill=DG)
    d.rectangle([16, 13, 18, 16], fill=LG)
    d.line([(16, 13), (16, 16)], fill=W)
    # highlights
    d.line([(6, 4), (14, 4)], fill=W)
    d.line([(17, 12), (17, 24)], fill=W)
    return outline(im)


def i_titan():
    im, d = canvas()
    pts(d, [(17, 29), (22, 12), (31, 29)], DG)          # back peak
    pts(d, [(22, 12), (25, 17), (21, 17)], LG)
    pts(d, [(1, 29), (15, 4), (31, 29)], DG)            # base shadow
    pts(d, [(1, 29), (15, 4), (17, 29)], LG)            # lit face
    pts(d, [(15, 4), (17, 29), (31, 29), (22, 18)], DG)
    pts(d, [(15, 4), (10, 13), (13, 12), (15, 16), (18, 12), (20, 13)], W)
    pts(d, [(15, 4), (20, 13), (18, 12), (15, 16)], LG)
    d.line([(8, 20), (12, 17)], fill=DG)
    d.line([(6, 25), (11, 22)], fill=DG)
    d.line([(21, 22), (26, 26)], fill=LG)
    d.rectangle([1, 28, 31, 29], fill=DGR)
    d.line([(1, 28), (31, 28)], fill=G)
    return outline(im)


def i_sniper():
    im, d = canvas()
    disc(d, 15.5, 15.5, 11, R)
    disc(d, 15.5, 15.5, 8, DG)
    d.arc([8, 8, 23, 23], 180, 270, fill=LG, width=2)
    for box in ([14, 1, 17, 11], [14, 20, 17, 30], [1, 14, 11, 17], [20, 14, 30, 17]):
        d.rectangle(box, fill=R)
    d.line([(15, 8), (15, 13)], fill=W)
    d.line([(15, 18), (15, 23)], fill=W)
    d.line([(8, 15), (13, 15)], fill=W)
    d.line([(18, 15), (23, 15)], fill=W)
    disc(d, 15.5, 15.5, 1.5, R)
    d.rectangle([15, 15, 16, 16], fill=W)
    d.line([(7, 6), (10, 4)], fill=PK)
    return outline(im)


def i_hunter():
    im, d = canvas()
    # bow bulging right
    d.arc([2, 1, 26, 30], 280, 80, fill=BR, width=4)
    d.arc([4, 3, 24, 28], 290, 70, fill=O, width=1)
    # string pulled to nock
    d.line([(21, 3), (7, 16)], fill=LG)
    d.line([(7, 16), (21, 28)], fill=LG)
    # arrow
    d.line([(7, 15), (26, 15)], fill=Y, width=2)
    pts(d, [(25, 11), (31, 15.5), (25, 20)], LG)
    pts(d, [(25, 11), (31, 15.5), (27, 15.5)], W)
    pts(d, [(1, 10), (9, 15), (1, 21)], R)
    d.line([(2, 12), (7, 15)], fill=PK)
    return outline(im)


def i_swift():
    im, d = canvas()
    for y, x0, x1 in ((6, 1, 9), (13, 1, 6), (20, 2, 8), (27, 1, 12)):
        d.line([(x0, y), (x1, y)], fill=C, width=2)
        d.line([(x0, y), (x0 + (x1 - x0) // 2, y)], fill=W)
    bolt = [(24, 1), (10, 18), (17, 18), (13, 30), (30, 11), (21, 11), (27, 1)]
    pts(d, bolt, O)
    pts(d, [(24, 1), (13, 16), (17, 16), (15, 24), (26, 11), (21, 11), (25, 3)], Y)
    d.line([(24, 3), (14, 16)], fill=W)
    return outline(im)


def i_aegis():
    im, d = canvas()
    outer = [(3, 3), (28, 3), (28, 16), (24, 24), (15.5, 30), (7, 24), (3, 16)]
    inner = [(6, 6), (25, 6), (25, 16), (22, 22), (15.5, 27), (9, 22), (6, 16)]
    pts(d, outer, LG)
    pts(d, [(15.5, 3), (28, 3), (28, 16), (24, 24), (15.5, 30)], DG)
    pts(d, inner, B)
    pts(d, [(6, 6), (15.5, 6), (15.5, 27), (9, 22), (6, 16)], C)
    d.line([(7, 7), (7, 15)], fill=W)
    d.line([(8, 7), (13, 7)], fill=W)
    # emblem: star
    pts(d, [(15.5, 10), (17, 14), (21, 14), (18, 17), (19, 21), (15.5, 18.5),
            (12, 21), (13, 17), (10, 14), (14, 14)], Y)
    d.point((15, 13), fill=W)
    d.point((15, 14), fill=W)
    return outline(im)


def i_stasis():
    im, d = canvas()
    cx = cy = 15.5
    for k in range(6):
        a = math.radians(60 * k)
        ux, uy = math.cos(a), math.sin(a)
        px, py = -uy, ux
        ex, ey = cx + ux * 14, cy + uy * 14
        d.line([(cx, cy), (ex, ey)], fill=C, width=3)
        for t, ln in ((0.5, 5.5), (0.78, 4.0)):
            bx, by = cx + ux * 14 * t, cy + uy * 14 * t
            for s in (-1, 1):
                fx = bx + (ux * 0.6 + px * s * 0.8) * ln
                fy = by + (uy * 0.6 + py * s * 0.8) * ln
                d.line([(bx, by), (fx, fy)], fill=C, width=2)
    for k in range(6):
        a = math.radians(60 * k)
        d.line([(cx, cy), (cx + math.cos(a) * 12, cy + math.sin(a) * 12)], fill=W)
    disc(d, cx, cy, 3, B)
    disc(d, cx, cy, 2, W)
    return outline(im)


def i_chrono():
    im, d = canvas()
    glass = [(7, 6), (24, 6), (17, 15), (17, 17), (24, 26), (7, 26), (14, 17), (14, 15)]
    pts(d, glass, LG)
    d.line([(8, 7), (14, 14)], fill=W)
    d.line([(8, 25), (13, 19)], fill=W)
    pts(d, [(10, 8), (21, 8), (16, 14)], Y)           # top sand
    pts(d, [(10, 8), (21, 8), (20, 9), (11, 9)], O)
    d.line([(15, 14), (15, 19)], fill=Y)
    d.line([(16, 14), (16, 19)], fill=O)
    pts(d, [(9, 25), (22, 25), (16, 19)], Y)          # bottom pile
    pts(d, [(16, 19), (22, 25), (16, 25)], O)
    for (y0, y1) in ((1, 5), (27, 31)):
        d.rectangle([4, y0, 27, y1], fill=BR)
        d.line([(4, y0), (27, y0)], fill=Y)
        d.line([(4, y1), (27, y1)], fill=O if False else BR)
    d.line([(5, 2), (12, 2)], fill=W)
    return outline(im)


def i_phoenix():
    im, d = canvas()
    # wings (fiery), feathered
    for sgn in (-1, 1):
        def X(x): return 15.5 + sgn * (x - 15.5)
        pts(d, [(X(9), 14), (X(1), 2), (X(4), 9), (X(0), 10), (X(4), 15),
                (X(1), 19), (X(7), 21), (X(11), 22)], O)
        pts(d, [(X(9), 14), (X(3), 5), (X(5), 11), (X(3), 14), (X(7), 17)], Y)
        pts(d, [(X(9), 16), (X(3), 17), (X(2), 19), (X(8), 20)], R)
    # flame crest
    pts(d, [(16, 1), (20, 7), (18, 9), (13, 9), (11, 7)], O)
    pts(d, [(16, 3), (18, 7), (16, 9), (14, 7)], Y)
    heart(d, 16, 14, 17, R)
    heart(d, 16, 15, 14, PK) if False else None
    d.line([(10, 11), (12, 9)], fill=PK, width=2)
    d.point((13, 9), fill=W)
    pts(d, [(16, 28), (11, 21), (21, 21)], R)
    d.line([(21, 14), (17, 24)], fill=BR)
    return outline(im)


def i_lucky():
    im, d = canvas()
    cx = cy = 15.5
    d.line([(16, 16), (17, 24), (21, 30)], fill=DGR, width=3)
    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        n = math.hypot(dx, dy)
        ux, uy = dx / n, dy / n
        px, py = -uy, ux
        l1 = (cx + ux * 8 + px * 4, cy + uy * 8 + py * 4)
        l2 = (cx + ux * 8 - px * 4, cy + uy * 8 - py * 4)
        pts(d, [(cx, cy), l1, l2], G)
        disc(d, l1[0], l1[1], 5, G)
        disc(d, l2[0], l2[1], 5, G)
    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        d.line([(cx, cy), (cx + dx * 9, cy + dy * 9)], fill=DGR)
    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        d.line([(cx + dx * 7.5, cy + dy * 7.5), (cx + dx * 15, cy + dy * 15)], fill=0, width=2)
    d.line([(6, 8), (9, 6)], fill=W)
    d.point((7, 7), fill=W)
    d.line([(23, 6), (25, 8)], fill=Y)
    disc(d, cx, cy, 1.5, DGR)
    return outline(im)


def i_prism():
    im, d = canvas()
    # incoming white beam
    d.line([(1, 22), (9, 18)], fill=W, width=2)
    # rainbow rays
    cols = [R, O, Y, G, B, P]
    for k, c in enumerate(cols):
        y0 = 12 + k * 1.6
        y1 = 4 + k * 4.6
        pts(d, [(17, y0), (31, y1), (31, y1 + 4.6), (17, y0 + 1.7)], c)
    # prism
    tri = [(4, 28), (12, 3), (22, 28)]
    pts(d, tri, LG)
    pts(d, [(12, 3), (22, 28), (14, 28)], DG)
    pts(d, [(12, 3), (4, 28), (9, 28)], W)
    pts(d, [(12, 3), (9, 28), (14, 28)], C)
    d.line([(12, 6), (7, 24)], fill=W)
    return outline(im)


def i_glass():
    im, d = canvas()
    heart(d, 16, 14, 28, C)
    heart(d, 16, 13, 22, W) if False else None
    # facets
    pts(d, [(16, 28), (27, 14), (16, 14)], B)
    d.line([(6, 8), (9, 5)], fill=W, width=2)
    d.line([(5, 11), (5, 13)], fill=W)
    # crack
    zig = [(17, 4), (15, 9), (19, 13), (14, 18), (18, 22), (16, 27)]
    d.line(zig, fill=K, width=2)
    d.line([(15, 9), (11, 11)], fill=K)
    d.line([(19, 13), (24, 13)], fill=K)
    # chip
    pts(d, [(24, 5), (28, 9), (25, 9)], 0)
    return outline(im)


def i_quota():
    im, d = canvas()
    d.rectangle([6, 2, 8, 29], fill=LG)
    d.line([(6, 2), (6, 29)], fill=W)
    d.line([(8, 2), (8, 29)], fill=DG)
    disc(d, 7, 2, 2, Y)
    # flag with wavy end
    top = [(9, 4), (28, 4)]
    wave = [(28, 4), (26, 7), (29, 11), (27, 15), (28, 18)]
    pts(d, [(9, 4), (28, 4), (26, 7), (29, 11), (27, 15), (28, 18), (9, 18)], R)
    pts(d, [(9, 14), (27, 15), (28, 18), (9, 18)], O if False else R)
    d.line([(9, 5), (26, 5)], fill=PK)
    d.line([(9, 17), (27, 17)], fill=BR)
    disc(d, 18, 11, 5, W)
    disc(d, 18, 11, 3, R)
    disc(d, 18, 11, 1, W)
    d.ellipse([3, 27, 12, 31], fill=DG)
    d.rectangle([3, 29, 12, 29], fill=DG)
    d.line([(4, 28), (11, 28)], fill=LG)
    return outline(im)


def i_jackpot():
    im, d = canvas()
    d.rounded_rectangle([3, 9, 28, 20], radius=6, fill=O)
    d.rectangle([3, 15, 28, 20], fill=O)
    d.rectangle([3, 18, 28, 29], fill=BR)
    d.rectangle([3, 18, 28, 19], fill=Y)
    for x in (5, 22):
        d.rectangle([x, 9 if False else 10, x + 3, 29], fill=Y)
        d.line([(x + 3, 12), (x + 3, 29)], fill=O)
    d.line([(8, 11), (11, 10)], fill=W)
    d.line([(12, 11), (19, 11)], fill=Y)
    d.rectangle([13, 16, 18, 24], fill=Y)
    d.rectangle([13, 16, 13, 24], fill=W)
    d.rectangle([15, 19, 16, 22], fill=K)
    d.rectangle([3, 28, 28, 29], fill=BR)
    sparkle(d, 4, 4, 3)
    sparkle(d, 28, 3, 2)
    sparkle(d, 17, 3, 2, Y)
    return outline(im)


def i_midas():
    im, d = canvas()
    pts(d, [(4, 24), (3, 8), (10, 15), (15.5, 4), (21, 15), (28, 8), (27, 24)], Y)
    pts(d, [(15.5, 4), (21, 15), (28, 8), (27, 24), (15.5, 24)], O)
    pts(d, [(3, 8), (10, 15), (4, 24)], Y)
    d.rectangle([4, 21, 27, 28], fill=Y)
    d.rectangle([4, 26, 27, 28], fill=O)
    d.line([(4, 21), (27, 21)], fill=W)
    for x, c in ((4, W), (15.5, W), (28, W)):
        pass
    for cx, cy, c in ((3, 7, W), (15.5, 3, W), (28, 7, W)):
        disc(d, cx, cy, 2, c)
    d.point((15, 3), fill=Y)
    for x, c in ((8, B), (15, R), (23, B)):
        d.rectangle([x, 23, x + 2, 25], fill=c)
        d.point((x, 23), fill=W)
    d.line([(6, 12), (8, 19)], fill=W)
    return outline(im)


ICONS = [i_greed, i_chain, i_titan, i_sniper, i_hunter, i_swift, i_aegis,
         i_stasis, i_chrono, i_phoenix, i_lucky, i_prism, i_glass, i_quota,
         i_jackpot, i_midas]

# ---------------------------------------------------------------- minis
# 1 = main, 2 = dark, 3 = accent
MINIS = [
    # 0 GREED (row 0 left blank: the SNES hides scanline 0)
    ['........', '..1111..', '.133331.', '..1111..', '.133331.', '..1111..', '.133331.', '..1111..'],
    # 1 CHAIN (row 0 left blank: the SNES hides scanline 0)
    ['........', '.111....', '1...1...', '1..111..', '.111..1.', '...1..1.', '....111.', '........'],
    # 2 TITAN (row 0 left blank: the SNES hides scanline 0)
    ['........', '...1....', '..131...', '.13331..', '.1...11.', '1.....11', '1......1', '11111111'],
    # 3 SNIPER (row 0 left blank: the SNES hides scanline 0)
    ['........', '..111...', '.1.1.1..', '1..1..1.', '1113111.', '1..1..1.', '.1.1.1..', '..111...'],
    # 4 HUNTER (row 0 left blank: the SNES hides scanline 0)
    ['........', '.....111', '......11', '.....1.1', '....1...', '.3.1....', '..1.....', '.3.3....'],
    # 5 SWIFT (row 0 left blank: the SNES hides scanline 0)
    ['........', '....11..', '...11...', '..1111..', '...11...', '..11....', '.11.....', '.1......'],
    # 6 AEGIS (row 0 left blank: the SNES hides scanline 0)
    ['........', '.111111.', '.133331.', '.133331.', '.133331.', '..1331..', '...11...', '........'],
    # 7 STASIS (row 0 left blank: the SNES hides scanline 0)
    ['...1....', '.1.1.1..', '..111...', '1113111.', '..111...', '.1.1.1..', '...1....', '........'],
    # 8 CHRONO (row 0 left blank: the SNES hides scanline 0)
    ['........', '.111111.', '..1331..', '...11...', '...11...', '..1331..', '.111111.', '........'],
    # 9 PHOENIX (row 0 left blank: the SNES hides scanline 0)
    ['........', '.11.11..', '1331331.', '1333331.', '.13331..', '..131...', '...1....', '........'],
    # 10 LUCKY (row 0 left blank: the SNES hides scanline 0)
    ['........', '.11.11..', '1331331.', '.11311..', '1331331.', '.11.11..', '...1....', '....1...'],
    # 11 PRISM (row 0 left blank: the SNES hides scanline 0)
    ['........', '...1....', '..131..3', '..131.3.', '.133313.', '.13331..', '1111111.', '........'],
    # 12 GLASS (row 0 left blank: the SNES hides scanline 0)
    ['........', '.11.11..', '1..1..1.', '1.1...1.', '.1.1.1..', '..1.1...', '...1....', '........'],
    # 13 QUOTA (row 0 left blank: the SNES hides scanline 0)
    ['........', '.11111..', '.13331..', '.11111..', '.1......', '.1......', '.1......', '111.....'],
    # 14 JACKPOT (row 0 left blank: the SNES hides scanline 0)
    ['........', '.111111.', '13333331', '11111111', '13311331', '13333331', '11111111', '........'],
    # 15 MIDAS (row 0 left blank: the SNES hides scanline 0)
    ['........', '1..1..1.', '11.1.11.', '1111111.', '1313131.', '1111111.', '........', '........'],
]


def main():
    sheet = Image.new("P", (128, 128), 0)
    for i, fn in enumerate(ICONS):
        sheet.paste(fn(), ((i % 4) * 32, (i // 4) * 32))
    a = np.array(sheet, dtype=np.uint8)
    data = bytearray()
    for ty in range(16):
        for tx in range(16):
            data += tile4(a[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8])
    assert len(data) == 8192
    pal = pal_bytes(PAL)
    assert len(pal) == 32
    mdata = bytearray()
    for m in MINIS:
        assert len(m) == 8 and all(len(r) == 8 for r in m)
        px = [[0 if ch == "." else int(ch) for ch in r] for r in m]
        mdata += tile2(px)
    assert len(mdata) == 256
    for name, b in (("icons.bin", data), ("iconpal.bin", pal), ("minis.bin", mdata)):
        with open(os.path.join(OUT, name), "wb") as f:
            f.write(b)

    bg = (40, 44, 64)
    lut = [bg] + [tuple(c) for c in PAL[1:]]
    rgb = np.array(lut, dtype=np.uint8)[a]
    Image.fromarray(rgb, "RGB").resize((512, 512), Image.NEAREST).save(
        os.path.join(OUT, "icons_preview.png"))
    Image.fromarray(rgb, "RGB").save(os.path.join(OUT, "icons_preview_1x.png"))

    mlut = [(88, 92, 104), (255, 255, 255), (16, 24, 96), (130, 200, 255)]
    mim = np.zeros((8, 8 * 16), dtype=np.uint8)
    for i, m in enumerate(MINIS):
        for y, r in enumerate(m):
            for x, ch in enumerate(r):
                mim[y, i * 8 + x] = 0 if ch == "." else int(ch)
    Image.fromarray(np.array(mlut, dtype=np.uint8)[mim], "RGB").resize(
        (128 * 8, 64), Image.NEAREST).save(os.path.join(OUT, "minis_preview.png"))
    print("ok", len(data), len(pal), len(mdata))


main()
