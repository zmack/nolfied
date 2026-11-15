#!/usr/bin/env python3
"""Compare the C scoring module (experiments/c-trial) with the assembly one.

Both ROMs score the same 40 claim scenarios (experiments/c-trial/vectors.bin).
Every result is checked against an independent Python model, and every call
is timed with the PPU H/V counters (NTSC: 262 lines of 1364 master cycles,
the frame counter ticks at the start of vblank, line 225).

Usage: python3 tools/bench_score.py      (or: make bench)
"""
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(__file__))
from retro import Emu  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRIAL = os.path.join(ROOT, "experiments", "c-trial")
MASTER_HZ = 21_477_272
LINE, FRAME = 1364, 1364 * 262


def model(chips, chain, kills, jack, owned, s):
    plus = (1 + chain * (1 + s[1]) + 2 * s[0] + (6 * s[3] if chips < 40 else 0)
            + 3 * s[4] * kills + s[11] * owned + jack)
    xm = (1 + s[2] if chips >= 150 else 1) * (3 if s[12] else 1)
    mult = min(plus * xm, 999)
    return mult, chips * mult


def stamp(h, v, f):
    """absolute master-cycle time from a (H, V, frame counter) sample"""
    return f * FRAME + ((v - 225) % 262) * LINE + h * 4


def elapsed(a, b):
    return (stamp(*b) - stamp(*a)) % (256 * FRAME)


def bcd(b):
    return int(b[::-1].hex())


CAL = {}


def run(rom, ram_base, done_addr, rec_len, parse, calib):
    e = Emu(rom)
    for _ in range(120):
        e.run(5)
        if e.wram()[done_addr]:
            break
    else:
        raise SystemExit(f"{rom}: benchmark did not finish")
    m = e.wram()
    CAL[rom] = calib(m)
    return [parse(m[ram_base + i * rec_len: ram_base + (i + 1) * rec_len]) for i in range(N)]


vec = open(os.path.join(TRIAL, "vectors.bin"), "rb").read()
N = len(vec) // 24
vectors = [struct.unpack("<HBBHBB16B", vec[i * 24:(i + 1) * 24]) for i in range(N)]

# ---- C: addresses from the linker's cross reference
xref = open(os.path.join(TRIAL, "ln65816.lst")).read()
addr = {n: int(a, 16) for n, a in re.findall(r"^\s+(\w+) = ([0-9A-Fa-f]+)$", xref, re.M)}


def parse_c(r):
    mult, pts, h0, v0, f0, h1, v1, f1 = struct.unpack("<HIHHBHHB", r)
    return mult, pts, elapsed((h0, v0, f0), (h1, v1, f1))


def parse_asm(r):
    mult = r[0] | r[1] << 8
    pts = bcd(r[2:6])
    t0 = (r[6] | r[7] << 8, r[8] | r[9] << 8, r[10])
    t1 = (r[11] | r[12] << 8, r[13] | r[14] << 8, r[15])
    tm = (r[16] | r[17] << 8, r[18] | r[19] << 8, r[20])
    return mult, pts, elapsed(t0, tm), elapsed(t0, t1)


def calib_c(m):
    return parse_c(m[addr["calib"]:addr["calib"] + 16])[2]


def calib_asm(m):
    return parse_asm(m[0x8F00:0x8F00 + 24])[2]


c_rom = os.path.join(TRIAL, "bench.sfc")
a_rom = os.path.join(ROOT, "build", "nolfied_bench.sfc")
c_res = run(c_rom, addr["results"], addr["bench_done"], 16, parse_c, calib_c)
a_res = run(a_rom, 0x8000, 0x8FFF, 24, parse_asm, calib_asm)
# subtract each harness's own empty-window cost
c_res = [(m, p, t - CAL[c_rom]) for m, p, t in c_res]
a_res = [(m, p, t - CAL[a_rom], u - CAL[a_rom]) for m, p, t, u in a_res]
print(f"harness overhead subtracted: C {CAL[c_rom] * 1e6 / MASTER_HZ:.1f} us, "
      f"asm {CAL[a_rom] * 1e6 / MASTER_HZ:.1f} us")

fails = 0
print(f"{'#':>2} {'chips':>5} {'mult':>4} {'points':>8} | {'C us':>7} {'asm math us':>11} {'asm total us':>12}  check")
us = lambda mc: mc * 1e6 / MASTER_HZ
QUIET = "--quiet" in sys.argv
for i, v in enumerate(vectors):
    chips, chain, kills, jack, owned, _pad, *stacks = v
    want = model(chips, chain, kills, jack, owned, stacks)
    c, a = c_res[i], a_res[i]
    ok = (c[0], c[1]) == want and (a[0], a[1]) == want
    fails += not ok
    if QUIET and ok:
        continue
    print(f"{i:2} {chips:5} {want[0]:4} {want[1]:8} | {us(c[2]):7.1f} {us(a[2]):11.1f} {us(a[3]):12.1f}  "
          f"{'ok' if ok else f'MISMATCH c={c[:2]} asm={a[:2]}'}")

ct = sum(us(r[2]) for r in c_res) / N
am = sum(us(r[2]) for r in a_res) / N
at = sum(us(r[3]) for r in a_res) / N
print(f"\nmean per claim: C {ct:.1f} us, asm arithmetic {am:.1f} us (asm incl. popup/juice {at:.1f} us)")
print(f"one frame is {1e6 / 60.0988:.0f} us; a claim happens at most once per cut")
ratios = sorted(c_res[i][2] / a_res[i][2] for i in range(N))
slower = sum(r > 1.0 for r in ratios)
print(f"C / asm-arithmetic time: best {ratios[0]:.2f}x, median {ratios[N // 2]:.2f}x, "
      f"worst {ratios[-1]:.2f}x; C slower in {slower}/{N} scenarios")
print(f"\n{'OK' if not fails else 'FAILED'}: {N - fails}/{N} scenarios match the model in both ROMs")
sys.exit(1 if fails else 0)
