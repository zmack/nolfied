#!/usr/bin/env python3
"""The SPC700's sample set: synthesised here, BRR-encoded, laid out for the
sound CPU's RAM.

  build/spc_dir.bin      the DSP sample directory at $0300 (64 entries of
                         start, loop: 4 bytes each)
  build/spc_samples.bin  the BRR data, from $0400
  build/spc_samples.h    SAMPLE_* numbers for C

Sample 0 and 1 are the original sound-effect waveforms, byte for byte, so the
effects sound as before. The rest are the music's instruments: band-limited
saw and pulse waves, minor and major chord stabs (one period of a chord
holds harmonics 16/19/24 or 16/20/24 of its loop, so both stay in tune when
transposed), and drum-machine one-shots.

Usage: gen_samples.py OUTDIR
"""
import math
import os
import random
import sys

import numpy as np

OUT = sys.argv[1] if len(sys.argv) > 1 else "build"
DIR_ADDR, DATA_ADDR = 0x0300, 0x0400
rng = np.random.default_rng(1983)

# ---- BRR -----------------------------------------------------------------------
# Decoder as in the S-DSP (blargg's spc_dsp): buffer values are doubled
# 15-bit samples. The encoder tries every (shift, filter) per block of 16
# samples and keeps the one whose decode is closest.


def clamp16(v):
    return -32768 if v < -32768 else 32767 if v > 32767 else v


def to_i16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def decode_one(nib, shift, filt, p1, p2):
    s = (nib << shift) >> 1 if shift <= 12 else (-2048 if nib < 0 else 0)
    p2h = p2 >> 1
    if filt == 1:
        s += p1 >> 1
        s += (-p1) >> 5
    elif filt == 2:
        s += p1
        s -= p2h
        s += p2h >> 4
        s += (p1 * -3) >> 6
    elif filt == 3:
        s += p1
        s -= p2h
        s += (p1 * -13) >> 7
        s += (p2h * 3) >> 4
    return to_i16(clamp16(s) * 2)


def encode_block(x, p1, p2, filters):
    best = None
    for filt in filters:
        for shift in range(0, 13):
            q1, q2, err, nibs = p1, p2, 0, []
            for v in x:
                # the nibble that decodes closest: the rounded guess, +-1
                base = decode_one(0, shift, filt, q1, q2)
                guess = min(7, max(-8, int(round((v - base) / (1 << shift)))))
                bestn, beste, bests = 0, None, 0
                for nib in range(max(-8, guess - 1), min(7, guess + 1) + 1):
                    s = decode_one(nib, shift, filt, q1, q2)
                    e = abs(s - v)
                    if beste is None or e < beste:
                        bestn, beste, bests = nib, e, s
                nibs.append(bestn)
                err += beste * beste
                q2, q1 = q1, bests
                if best is not None and err >= best[0]:
                    break
            else:
                if best is None or err < best[0]:
                    best = (err, shift, filt, nibs, q1, q2)
    _, shift, filt, nibs, q1, q2 = best
    return shift, filt, nibs, q1, q2


def brr(samples, loop):
    """samples: ints in the doubled 16-bit domain (|v| < 30000)"""
    x = [int(v) for v in samples]
    if len(x) % 16:
        x += [0] * (16 - len(x) % 16)
    out = bytearray()
    p1 = p2 = 0
    nblocks = len(x) // 16
    for b in range(nblocks):
        blk = x[b * 16:(b + 1) * 16]
        filters = (0,) if b == 0 else (0, 1, 2, 3)
        shift, filt, nibs, p1, p2 = encode_block(blk, p1, p2, filters)
        hdr = (shift << 4) | (filt << 2)
        if b == nblocks - 1:
            hdr |= 1 | (2 if loop else 0)
        out.append(hdr)
        for i in range(0, 16, 2):
            out.append(((nibs[i] & 15) << 4) | (nibs[i + 1] & 15))
    return bytes(out)


# ---- the instruments ----------------------------------------------------------

def norm(w, peak):
    w = np.asarray(w, dtype=float)
    return np.round(w / np.max(np.abs(w)) * peak).astype(int)


def saw(n, base=1, amp=1.0):
    """band-limited saw with fundamental `base` cycles per n samples"""
    t = np.arange(n) / n
    w = np.zeros(n)
    k = 1
    while k * base < n // 2:
        w += amp * np.sin(2 * math.pi * k * base * t) / k
        k += 1
    return w


def pulse(n, duty):
    t = np.arange(n) / n
    w = np.zeros(n)
    for k in range(1, n // 2):
        w += np.sin(math.pi * k * duty) / k * np.cos(2 * math.pi * k * (t - duty / 2))
    return w - w.mean()


def chord(tones):
    n = 512
    w = saw(n, 8, 0.55)                       # an octave below the root, for weight
    for h in tones:
        w += saw(n, h, 1.0)
    return w


def env_decay(n, rate, tau):
    t = np.arange(n) / rate
    return np.exp(-t / tau)


def kick():
    rate, n = 16000, 2400
    t = np.arange(n) / rate
    f = 46 + 120 * np.exp(-t / 0.028)
    phase = 2 * math.pi * np.cumsum(f) / rate
    w = np.sin(phase) * np.exp(-t / 0.13)
    click = rng.standard_normal(n) * np.exp(-t / 0.0015) * 0.5
    return w + click


def snare():
    rate, n = 16000, 2560
    t = np.arange(n) / rate
    noise = rng.standard_normal(n)
    noise = np.convolve(noise, [0.5, 1, 0.5], "same")          # a little darker
    body = np.sin(2 * math.pi * 185 * t) * np.exp(-t / 0.035)
    return noise * np.exp(-t / 0.055) * 0.8 + body * 0.9


def hat():
    rate, n = 32000, 1120
    t = np.arange(n) / rate
    noise = rng.standard_normal(n)
    hp = noise - np.convolve(noise, np.ones(4) / 4, "same")     # high-pass
    return hp * np.exp(-t / 0.011)


def clank():
    """an inharmonic metal hit: the industrial accent"""
    rate, n = 16000, 2560
    t = np.arange(n) / rate
    w = np.zeros(n)
    for f, a in ((331, 1.0), (797, 0.8), (1213, 0.7), (1789, 0.5), (2411, 0.4)):
        w += a * np.sin(2 * math.pi * f * t + rng.uniform(0, 6.28))
    w *= np.exp(-t / 0.07)
    w += rng.standard_normal(n) * np.exp(-t / 0.004) * 0.6
    return w


PEAK = 14000
# (name, waveform, loops)
MUSIC = [
    ("SAW", norm(saw(64), PEAK), True),
    ("PULSE", norm(pulse(64, 0.25), PEAK), True),
    ("CHORD_MIN", norm(chord((16, 19, 24)), PEAK), True),
    ("CHORD_MAJ", norm(chord((16, 20, 24)), PEAK), True),
    ("KICK", norm(kick(), 16000), False),
    ("SNARE", norm(snare(), 15000), False),
    ("HAT", norm(hat(), 12000), False),
    ("CLANK", norm(clank(), 13000), False),
]

# the two original sound-effect waveforms (core.s, before the music)
SFX0 = bytes([0xB3, 0x77, 0x77, 0x77, 0x77, 0x99, 0x99, 0x99, 0x99]) + bytes(7)
SFX1 = bytes([0xB0, 0x01, 0x23, 0x45, 0x67, 0x76, 0x54, 0x32, 0x10,
              0xB3, 0xFE, 0xDC, 0xBA, 0x98, 0x89, 0xAB, 0xCD, 0xEF])

data = bytearray(SFX0 + SFX1)
entries = [(DATA_ADDR, DATA_ADDR), (DATA_ADDR + 16, DATA_ADDR + 16)]
for name, w, loop in MUSIC:
    addr = DATA_ADDR + len(data)
    data += brr(w, loop)
    entries.append((addr, addr))

assert DATA_ADDR + len(data) < 0x7000, "samples run into the echo buffer"
dirb = bytearray(256)
for i, (s, l) in enumerate(entries):
    dirb[4 * i:4 * i + 4] = bytes([s & 255, s >> 8, l & 255, l >> 8])

os.makedirs(OUT, exist_ok=True)
open(os.path.join(OUT, "spc_dir.bin"), "wb").write(dirb)
open(os.path.join(OUT, "spc_samples.bin"), "wb").write(data)
with open(os.path.join(OUT, "spc_samples.h"), "w") as h:
    h.write("/* generated by tools/gen_samples.py */\n")
    h.write("enum {\n    SAMPLE_SFX_SQUARE, SAMPLE_SFX_TRIANGLE,\n")
    for name, _, _ in MUSIC:
        h.write(f"    SAMPLE_{name},\n")
    h.write("};\n\n")
    # note names TIE (0), REST (1), C1 (2) .. B6, and the DSP pitch of each for
    # a 64-sample loop: P = f * 4096 * 64 / 32000 (the chord samples hold 32
    # samples per root cycle and use half)
    names = ["C", "Cs", "D", "Ds", "E", "F", "Fs", "G", "Gs", "A", "As", "B"]
    h.write("/* score symbols: __ holds the note, xx releases it */\n")
    h.write("enum { __ = 0, xx = 1,\n")
    notes = [f"{names[i % 12]}{i // 12 + 1}" for i in range(72)]
    for i in range(0, 72, 12):
        h.write("    " + ", ".join(f"{n} = {i + j + 2}" for j, n in enumerate(notes[i:i + 12])) + ",\n")
    h.write("};\n#define NOTE_FIRST C1\n\n")
    h.write("static const uint16_t note_pitch[72] = {\n")
    vals = []
    for i in range(72):
        f = 440.0 * 2 ** ((i + 12 - 57) / 12)        # A4 = index 45 from C1 -> 57 from C0
        vals.append(min(0x3FFF, round(f * 4096 * 64 / 32000)))
    for i in range(0, 72, 12):
        h.write("    " + ", ".join(str(v) for v in vals[i:i + 12]) + ",\n")
    h.write("};\n")
print(f"{OUT}/spc_samples.bin: {len(data)} bytes, {len(entries)} samples "
      f"(SPC RAM ${DATA_ADDR:04X}-${DATA_ADDR + len(data) - 1:04X})")
