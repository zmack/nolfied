#!/usr/bin/env python3
"""Run the self-tests built into the PROFILE ROM (src/selftest.c).

  box_scan (core.s)            against a C model, on random grids
                               (states 0..7, so values the game never stores
                               are covered too) and random boxes
  put_num / put_score / dec2   against plain % 10, on random values

A batch takes several frames (the models are slow); the ROM clears
prof_bench when it is done. Run: make selftest
"""
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


def w(m, a):
    return m[a] | m[a + 1] << 8


def batch(e, kind):
    e.poke(lab["freeze"], (5000).to_bytes(2, "little"))
    e.poke(lab["invuln"], (5000).to_bytes(2, "little"))
    e.poke(lab["prof_bench"], bytes([kind]))
    for _ in range(600):
        e.run(1)
        if e.wram()[lab["prof_bench"]] == 0:
            return
    sys.exit(f"self-test {kind} did not finish")


def results(e):
    m = e.wram()
    return w(m, lab["selftest_runs"]), w(m, lab["selftest_errs"]), m


def boot():
    e = Emu(os.path.join(ROOT, "build", "prof", "nolfied.sfc"))
    e.run(90); e.run(3, "start"); e.run(60); e.run(2, "b"); e.run(140)
    return e


ok = True
rnd = random.Random(7)

e = boot()
for f in range(30):
    hi = 8 if f % 4 == 3 else 4          # mostly real-looking states
    e.poke(lab["grid"], bytes(rnd.randrange(hi) for _ in range(48 * 64)))
    batch(e, 2)
runs, errs, m = results(e)
bad = list(m[lab["selftest_bad"]:lab["selftest_bad"] + 6])
print(f"box_scan: {runs} boxes, {errs} mismatch(es)"
      + (f", first: box {bad[:4]} want {bad[4]:#x} got {bad[5]:#x}" if errs else ""))
ok &= errs == 0 and runs >= 30 * 200

e = boot()
for f in range(20):
    batch(e, 3)
runs, errs, m = results(e)
print(f"numbers: {runs} values, {errs} wrong")
ok &= errs == 0 and runs >= 20 * 50

sys.exit(0 if ok else 1)
