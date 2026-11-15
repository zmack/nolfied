#!/usr/bin/env python3
"""Where the C game spends its frame (make profile).

Runs the PROFILE build with the same scripted play as tools/perf_compare.py
and reports, per stage of the main loop and of closing a cut, the mean and
max time in scanlines (one scanline = 1364 master cycles, about 170 CPU
cycles at 2.68 MHz)."""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from retro import Emu  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lab = {}
for line in open(os.path.join(ROOT, "build", "prof", "nolfied.lbl")):
    _, a, n = line.split()
    lab[n[1:]] = int(a, 16) & 0x1FFFF

LOOP = ["read_joy", "juice_update", "sfx_update", "run_state", "fsm_check", "build_oam"]
PLAY = ["player_update + calc_ppos", "enemies_update", "timers_update", "booms_update"]
CUT = ["field_fill (asm)", "pct + field_redraw_all (asm)", "check_enclosed", "score_claim",
       "snap_player", "draw_hud"]


def stamps(m):
    out = []
    for i in range(24):
        line = m[lab["prof_line"] + 2 * i] | m[lab["prof_line"] + 2 * i + 1] << 8
        out.append((m[lab["prof_frame"] + i], line))
    return out


def span(a, b):
    """scanlines from stamp a to stamp b; the frame counter ticks at line 225"""
    ta = a[0] * 262 + (a[1] - 225) % 262
    tb = b[0] * 262 + (b[1] - 225) % 262
    return (tb - ta) % (256 * 262)


def run(rom, read_stamps, lab_):
    e = Emu(rom)
    rnd = random.Random(4)
    e.run(90); e.run(3, "start"); e.run(60); e.run(2, "b"); e.run(140)
    loop = {k: [] for k in LOOP}
    play = {k: [] for k in PLAY}
    cut = {k: [] for k in CUT}
    last_cut = None
    frames = 0
    while frames < 2000:
        d = rnd.choice(["up", "down", "left", "right"])
        for _ in range(rnd.randint(4, 30)):
            e.poke(lab_["freeze"], (5000).to_bytes(2, "little"))
            e.run(1, d, "b")
            m = e.wram()
            if m[lab_["state"]] != 2:
                if m[lab_["state"]] in (0, 5):
                    e.run(3, "start"); e.run(60); e.run(2, "b"); e.run(140)
                continue
            frames += 1
            s = read_stamps(m)
            for i, k in enumerate(LOOP):
                v = span(s[i], s[i + 1])
                if v < 262:
                    loop[k].append(v)
            for i, k in enumerate(PLAY):
                v = span(s[16 + i], s[17 + i])
                if v < 262:
                    play[k].append(v)
            c = tuple(s[8:15])
            if c != last_cut and c[0] != (0, 0):
                last_cut = c
                parts = [span(c[i], c[i + 1]) for i in range(len(CUT))]
                if sum(parts) < 60 * 262:          # all seven stamps from one cut
                    for k, v in zip(CUT, parts):
                        cut[k].append(v)
    return loop, play, cut


def c_stamps(m):
    return stamps(m)


legacy_lab = {}
for line in open(os.path.join(ROOT, "build", "legacy", "nolfied_perf.lbl")):
    _, a_, n_ = line.split()
    legacy_lab[n_[1:]] = int(a_, 16) & 0x1FFFF


def legacy_stamps(m):
    return [(m[0x06C2 + 3 * i], m[0x06C0 + 3 * i] | m[0x06C1 + 3 * i] << 8) for i in range(24)]


def row(name, xs):
    if not xs:
        return f"  {name:30s} (not reached)"
    return f"  {name:30s} mean {sum(xs) / len(xs):6.1f}   max {max(xs):5d}"


C = run(os.path.join(ROOT, "build", "prof", "nolfied.sfc"), c_stamps, lab)
A = run(os.path.join(ROOT, "build", "legacy", "nolfied_perf.sfc"), legacy_stamps, legacy_lab)


def mean(xs):
    return sum(xs) / len(xs) if xs else float("nan")


print(f"scanlines per frame (mean / max)      {'C':>15s} {'assembly':>15s}")
for title, idx, keys in (("main loop", 0, LOOP), ("inside st_play", 1, PLAY)):
    print(title + ":")
    tc = ta = 0
    for k in keys:
        c, a_ = C[idx][k], A[idx][k]
        tc += mean(c); ta += mean(a_)
        print(f"  {k:34s} {mean(c):7.1f} / {max(c) if c else 0:4d}  {mean(a_):7.1f} / {max(a_) if a_ else 0:4d}")
    print(f"  {'total':34s} {tc:7.1f}         {ta:7.1f}")
print(f"closing a cut in C ({len(C[2][CUT[0]])} cuts), scanlines (262 = one frame):")
for k in CUT:
    print(row(k, C[2][k]))
