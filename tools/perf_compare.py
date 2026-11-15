#!/usr/bin/env python3
"""Per-frame CPU use of the C game vs the legacy all-assembly game.

Both ROMs record the scanline on which a frame's work finished (C:
`busy_line`; legacy PERF build: $06F8). Work starts right after the NMI at the
top of vblank (line 225), so (busy_line - 225) mod 262 is how many of the
frame's 262 scanlines the game used; whatever is left is headroom.

Both games get the same scripted input (cutting around the field, with the
enemies frozen so the run is not cut short), and the script reports:
  * busy scanlines per frame during play: mean, 95th percentile, max
  * how many frames each claim's fill takes (the main loop skips frames)

Usage: python3 tools/perf_compare.py     (or: make perf)
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from retro import Emu  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAMES = 2400


def labels(path):
    out = {}
    for line in open(path):
        _, a, n = line.split()
        a = int(a, 16)
        out[n[1:]] = a & 0x1FFFF if a >> 16 in (0x7E, 0x7F) else a
    return out


def measure(rom, lab, busy_addr, loops_addr, freeze_addr, play_state):
    e = Emu(rom)
    rnd = random.Random(4)
    e.run(90)
    e.run(3, "start")
    e.run(60)
    e.run(2, "b")                         # take a perk (C: draft; legacy: no-op)
    e.run(140)
    busy, fills = [], []
    w = lambda m, a: m[a] | m[a + 1] << 8
    prev_loops, stalled = None, 0
    plan = []
    while len(plan) < FRAMES:
        d = rnd.choice(["up", "down", "left", "right"])
        plan += [(d, "b")] * rnd.randint(4, 30)
    for btns in plan[:FRAMES]:
        e.poke(freeze_addr, (5000).to_bytes(2, "little"))
        e.run(1, *btns)
        m = e.wram()
        if m[lab["state"]] != play_state:
            if m[lab["state"]] in (0, 5):     # back on the title / game over: restart
                e.run(3, "start"); e.run(60); e.run(2, "b"); e.run(140)
            prev_loops = None
            continue
        loops = w(m, loops_addr)
        if prev_loops is not None and loops == prev_loops:
            stalled += 1                     # main loop still busy: a fill
        else:
            if stalled:
                fills.append(stalled + 1)
            stalled = 0
            busy.append((w(m, busy_addr) - 225) % 262)
        prev_loops = loops
    return busy, fills


def stats(xs):
    xs = sorted(xs)
    if not xs:
        return "n/a"
    return (f"mean {sum(xs) / len(xs):5.1f}  p95 {xs[int(len(xs) * 0.95)]:3d}  "
            f"max {xs[-1]:3d}   ({len(xs)} frames)")


c_lab = labels(os.path.join(ROOT, "build", "nolfied.lbl"))
l_lab = labels(os.path.join(ROOT, "build", "legacy", "nolfied_perf.lbl"))
runs = {
    "C (src/)": measure(os.path.join(ROOT, "build", "nolfied.sfc"), c_lab,
                        c_lab["busy_line"], c_lab["loops"], c_lab["freeze"], 2),
    "assembly (legacy/)": measure(os.path.join(ROOT, "build", "legacy", "nolfied_perf.sfc"), l_lab,
                                  0x06F8, 0x067A, l_lab["freeze"], 2),
}
print("busy scanlines per frame during play (of 262; NMI uploads included):")
for name, (busy, fills) in runs.items():
    print(f"  {name:20s} {stats(busy)}")
print("frames taken by a claim's fill (1 = no hitch):")
for name, (busy, fills) in runs.items():
    print(f"  {name:20s} {stats(fills) if fills else 'no multi-frame fills'}")
