#!/usr/bin/env python3
"""Hostile-input fuzzer.

Drives the ROM with input a real player would rarely produce: impossible
D-pad combinations (up+down, left+right), every button at once, buttons
flipping every frame, Start/Select mashing, and button storms timed around
state transitions. After every frame burst it checks that:

  * no illegal state transition / trail-invariant fault was recorded (FSM_ERRS)
  * the sound CPU is still answering (APU_DEAD)
  * state, player mode and player position are in range
  * the NMI and the main loop are both still running (no hang)
  * no timed state (READY, DYING, CLEAR, OVER) outlives its timer
  * the stack never grew into RAM it shouldn't touch
  * the field grid keeps its invariants whenever the player is on the edge

Usage: python3 tools/fuzz_input.py [SEED] [FRAMES]
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from retro import Emu  # noqa: E402

ALL = ["b", "y", "select", "start", "up", "down", "left", "right", "a", "x", "l", "r"]
DIRS = ["up", "down", "left", "right"]
CUT = ["b", "y", "a", "x"]
ST = {0: "TITLE", 1: "READY", 2: "PLAY", 3: "DYING", 4: "CLEAR", 5: "OVER",
      6: "DRAFT", 7: "PAUSE", 8: "BOOT"}
# longest a timed state may last, in frames (timer + forced-blank load slack)
MAX_STAY = {1: 120 + 30, 3: 90 + 30, 4: 240 + 30, 5: 300 + 30}
from syms import S  # noqa: E402
FSM_ERRS, FSM_KIND, FSM_FROM, FSM_TO, APU_DEAD, LOOPS = S.fsm_errs, S.fsm_kind, S.fsm_from, S.fsm_to, S.apu_dead, S.loops
# the C stack is the `stack` section (1KB, grows down from its end): its
# lowest 64 bytes must never be touched
STACK_LO = S.get("__stack_start")
STACK_GUARD = 64

seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
FRAMES = int(sys.argv[2]) if len(sys.argv) > 2 else 30000
rnd = random.Random(seed)

lab = {}
for line in open("build/nolfied.lbl"):
    _, a, n = line.split()
    lab[n[1:]] = int(a, 16)

e = Emu("build/nolfied.sfc")


def w16(m, a):
    return m[a] | m[a + 1] << 8


# ---- input generators: each yields a list of button names per frame -------
def g_noise(n):                       # every button independently random
    p = rnd.choice([0.1, 0.3, 0.5, 0.8])
    for _ in range(n):
        yield [b for b in ALL if rnd.random() < p]


def g_all(n):                         # everything held
    for _ in range(n):
        yield list(ALL)


def g_opposites(n):                   # impossible D-pad states, with or without cut
    combo = rnd.choice([["up", "down"], ["left", "right"], DIRS, ["up", "down", "left"]])
    cut = rnd.random() < 0.7
    for _ in range(n):
        yield combo + (["b"] if cut else [])


def g_flicker(n):                     # a button set that flips on/off every frame
    s = rnd.sample(ALL, rnd.randint(1, 5))
    for i in range(n):
        yield s if i % 2 == 0 else []


def g_cutflicker(n):                  # hold a direction, toggle the cut button each frame
    d = rnd.choice(DIRS)
    c = rnd.choice(CUT)
    for i in range(n):
        yield [d, c] if i % 2 == 0 else [d]


def g_mash(n):                        # Start/Select mashing on top of random play
    for i in range(n):
        yield [rnd.choice(["start", "select"])] + ([rnd.choice(DIRS)] if rnd.random() < 0.5 else []) \
            if rnd.random() < 0.5 else [rnd.choice(DIRS), "b"]


def g_play(n):                        # plausible play, so the game gets somewhere
    d = rnd.choice(DIRS)
    for _ in range(n):
        yield [d, "b"] if rnd.random() < 0.9 else [d]


def g_dirspin(n):                     # rotate through directions every frame while cutting
    for i in range(n):
        yield [DIRS[i % 4], "b"]


GENS = [g_noise, g_all, g_opposites, g_flicker, g_cutflicker, g_mash, g_play, g_play, g_dirspin]

# ---- checks -----------------------------------------------------------------
failures = []
state_since = {}
last_nmi = last_loops = None
stuck_nmi = stuck_loops = 0
cur_state = None
frames_in_state = 0
stats = {"frames": 0, "transitions": 0, "claims": 0, "deaths": 0, "max_stage": 0, "states": set()}


def fail(msg):
    failures.append((e.frames, msg))
    print(f"FAIL @frame {e.frames}: {msg}")
    e.shot(f"/tmp/fuzz_fail_{seed}_{len(failures)}.png")


def grid_ok(m):
    g = [[m[S.grid + y * 64 + x] for x in range(60)] for y in range(48)]
    for y in range(48):
        for x in range(60):
            v = g[y][x]
            if v > 3:
                return f"temp state {v} at {x},{y}"
            if v == 3:
                return f"trail left over at {x},{y}"
            if v in (1, 2):
                nb = [g[y + dy][x + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                      if (dy or dx) and 0 <= y + dy < 48 and 0 <= x + dx < 60]
                if v == 1 and 0 in nb:
                    return f"claimed cell next to open at {x},{y}"
                if v == 2 and 0 not in nb:
                    return f"orphan edge at {x},{y}"
    return None


def check(m):
    global cur_state, frames_in_state, last_nmi, last_loops, stuck_nmi, stuck_loops
    st = m[lab["state"]]
    stats["states"].add(ST.get(st, st))
    if m[FSM_ERRS]:
        fail(f"FSM fault kind={m[FSM_KIND]} from={m[FSM_FROM]} to={m[FSM_TO]} state={ST.get(st)}")
        e.poke(FSM_ERRS, b"\0")
    if m[APU_DEAD]:
        fail("sound CPU marked dead")
        e.poke(APU_DEAD, b"\0")
    if st not in ST:
        fail(f"state out of range: {st}")
    if m[lab["pmode"]] > 2:
        fail(f"pmode out of range: {m[lab['pmode']]}")
    p = w16(m, lab["p_idx"])
    if (p & 63) >= 60 or (p >> 6) >= 48:
        fail(f"player off the field: idx {p}")
    if w16(m, lab["trail_len"]) > 2700:
        fail(f"trail_len absurd: {w16(m, lab['trail_len'])}")
    if not 0 <= m[lab["lives"]] <= 9:
        fail(f"lives out of range: {m[lab['lives']]}")
    # stack depth: everything between the grid padding and $1F00 must be untouched
    deep = next((a for a in range(STACK_LO, STACK_LO + STACK_GUARD) if m[a]), None)
    if deep is not None:
        fail(f"stack grew down to ${deep:04X}")
    # liveness (not while booting: NMI comes on once the title screen is up)
    if st == 8:
        return
    nmi, loops = m[lab["nmi_count"]], w16(m, LOOPS)
    stuck_nmi = stuck_nmi + 1 if nmi == last_nmi else 0
    stuck_loops = stuck_loops + 1 if loops == last_loops else 0
    last_nmi, last_loops = nmi, loops
    if stuck_nmi > 3:
        fail("NMI stopped")
    if stuck_loops > 40:      # a fill may legitimately block for a while
        fail("main loop stopped")
    # timed states must not overstay
    if st != cur_state:
        if cur_state is not None:
            stats["transitions"] += 1
            if st == 3:
                stats["deaths"] += 1
        cur_state, frames_in_state = st, 0
    if st in MAX_STAY and frames_in_state > MAX_STAY[st]:
        fail(f"stuck in {ST[st]} for {frames_in_state} frames")
        frames_in_state = 0
    stats["max_stage"] = max(stats["max_stage"], m[lab["stage"]])
    if st == 2 and m[lab["pmode"]] == 0 and w16(m, lab["trail_len"]) == 0 and rnd.random() < 0.05:
        bad = grid_ok(m)
        if bad:
            fail("grid: " + bad)


claimed_prev = 0
while e.frames < FRAMES and len(failures) < 10:
    m = e.wram()
    st = m[lab["state"]]
    gen = rnd.choice(GENS)
    if st in (0, 5) and rnd.random() < 0.5:
        gen = g_mash                   # keep starting games
    # storm the transition frames: when a stage is nearly won, hammer everything
    if st == 2 and m[lab["pct"]] + 6 >= w16(m, S.goal) and rnd.random() < 0.5:
        gen = g_noise
    n = rnd.randint(1, 60)
    for btns in gen(n):
        e.run(1, *btns)
        frames_in_state += 1
        if e.frames % 4 == 0:
            check(e.wram())
    m = e.wram()
    check(m)
    c = w16(m, lab["claimed"])
    if c > claimed_prev:
        stats["claims"] += 1
    claimed_prev = c
    if rnd.random() < 0.002:           # occasionally help it reach later stages
        e.poke(lab["claimed"], (2550).to_bytes(2, "little"))

print(f"seed {seed}: {e.frames} frames, {stats['transitions']} transitions, "
      f"{stats['claims']} claims, {stats['deaths']} deaths, max stage {stats['max_stage']}, "
      f"states seen {sorted(stats['states'])}, failures {len(failures)}")
sys.exit(1 if failures else 0)
