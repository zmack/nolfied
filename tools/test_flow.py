#!/usr/bin/env python3
"""End-to-end game-flow regression test.

Walks the whole explicit state machine (BOOT, TITLE, DRAFT, READY, PLAY,
PAUSE, DYING, CLEAR, OVER) and asserts after every step that:
  * no illegal transition / trail invariant fault was recorded (FSM_ERRS)
  * the sound CPU is still answering (APU_DEAD)
  * the main loop runs exactly once per frame in steady play (no dropped
    frames: spec/FrameSync.tla)

Usage: python3 tools/test_flow.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from retro import Emu  # noqa: E402

ST = {0: "TITLE", 1: "READY", 2: "PLAY", 3: "DYING", 4: "CLEAR", 5: "OVER", 6: "DRAFT", 7: "PAUSE"}
FSM_ERRS, APU_DEAD, LOOPS, CLAIMED_FREEZE = 0x670, 0x678, 0x67A, None

lab = {}
for line in open("build/nolfied.lbl"):
    _, a, n = line.split()
    lab[n[1:]] = int(a, 16)

e = Emu("build/nolfied.sfc")
fails = 0


def r():
    return e.wram()


def w(addr):
    m = r()
    return m[addr] | m[addr + 1] << 8


def state():
    return ST.get(r()[lab["state"]], "?")


def check(name, cond, extra=""):
    global fails
    m = r()
    ok = cond and m[FSM_ERRS] == 0 and m[APU_DEAD] == 0
    if not ok:
        fails += 1
    print(f"{'PASS' if ok else 'FAIL'}  {name:38s} state={state():6s} fsm_errs={m[FSM_ERRS]} "
          f"apu_dead={m[APU_DEAD]} {extra}")


def freeze_enemies():
    e.poke(lab["freeze"], (30000).to_bytes(2, "little"))


e.run(90)
check("boot -> TITLE", state() == "TITLE")
e.run(3, "start"); e.run(20)
check("TITLE -> DRAFT", state() == "DRAFT")
e.run(50); e.run(2, "right"); e.run(2, "select"); e.run(5)
check("draft cursor + reroll stay in DRAFT", state() == "DRAFT")
e.run(2, "b"); e.run(12)   # the forced-blank stage load spans a few frames
check("DRAFT -> READY", state() == "READY")
e.run(130)
check("READY -> PLAY", state() == "PLAY")
freeze_enemies()

# frame pacing: in steady play the main loop must run once per frame
l0 = w(LOOPS); e.run(300); l1 = w(LOOPS)
check("no dropped frames over 300 frames", (l1 - l0) & 0xFFFF == 300, f"loops={(l1 - l0) & 0xFFFF}")

e.run(2, "start"); e.run(10)
check("PLAY -> PAUSE", state() == "PAUSE")
p0 = w(lab["p_idx"]); e.run(20, "up"); e.run(2, "start"); e.run(5)
check("PAUSE -> PLAY, input ignored while paused", state() == "PLAY" and w(lab["p_idx"]) == p0)

# cut, release (RETRACT) and re-press (DRAW) before closing
freeze_enemies()
e.run(20, "b", "up"); e.run(6); e.run(10, "b", "up")
check("DRAW -> RETRACT -> DRAW keeps invariant", r()[lab["pmode"]] in (1, 2))
e.run(30); e.run(20)
check("RETRACT -> EDGE when trail empties", r()[lab["pmode"]] == 0 and w(lab["trail_len"]) == 0)

# death: put a shard on our trail
freeze_enemies()
e.poke(lab["invuln"], b"\0\0"); e.run(12, "b", "up")
m = r(); p = w(lab["p_idx"]); px, py = (p & 63) * 4 + 2, (p >> 6) * 4 + 2
e.poke(0x502, bytes([0, px])); e.poke(0x512, bytes([0, py]))   # minion slot 1 onto the player
e.poke(0x542, b"\x02")
lives = r()[lab["lives"]]
e.run(3)
check("PLAY -> DYING on hit", state() == "DYING")
e.run(100)
check("DYING -> PLAY, life lost, trail wiped",
      state() == "PLAY" and r()[lab["lives"]] == lives - 1 and w(lab["trail_len"]) == 0)

# a claim
freeze_enemies()
e.run(40, "b", "up"); e.run(20, "b", "left"); e.run(60, "b", "down"); e.run(15)
check("DRAW -> EDGE on close, area claimed", r()[lab["pmode"]] == 0 and w(lab["claimed"]) > 0,
      f"claimed={w(lab['claimed'])}")

# stage clear
freeze_enemies()
e.poke(lab["claimed"], (2600).to_bytes(2, "little"))
e.run(10, "b", "up"); e.run(6, "b", "left"); e.run(40, "b", "down"); e.run(20)
check("PLAY -> CLEAR at goal", state() == "CLEAR")
e.run(250)
check("CLEAR -> DRAFT", state() == "DRAFT" and r()[lab["stage"]] == 2)
e.run(50); e.run(2, "b"); e.run(140)
check("DRAFT -> READY -> PLAY (stage 2)", state() == "PLAY")

# game over
e.poke(lab["lives"], b"\x01")
freeze_enemies()
e.poke(lab["invuln"], b"\0\0")
e.run(12, "b", "up")
p = w(lab["p_idx"]); px, py = (p & 63) * 4 + 2, (p >> 6) * 4 + 2
e.poke(0x502, bytes([0, px])); e.poke(0x512, bytes([0, py])); e.poke(0x542, b"\x02")
e.run(3)
check("last life: PLAY -> DYING", state() == "DYING")
e.run(100)
check("DYING -> OVER", state() == "OVER")
e.run(320)
check("OVER -> TITLE", state() == "TITLE")
e.run(3, "start"); e.run(20)
check("new run starts cleanly", state() == "DRAFT" and r()[lab["stage"]] == 1)

# negative test: the runtime checker must notice corrupted state
e.run(50); e.run(2, "b"); e.run(140)
e.poke(lab["pmode"], b"\x01"); e.poke(lab["trail_len"], b"\0\0")   # "cutting" with no trail
e.run(2)
m = r()
neg = m[FSM_ERRS] >= 1 and m[0x671] == 3
print(f"{'PASS' if neg else 'FAIL'}  checker flags a mode/trail mismatch     errs={m[FSM_ERRS]} kind={m[0x671]}")
fails += 0 if neg else 1

print(f"\n{'OK' if fails == 0 else 'FAILED'}: {fails} failure(s)")
sys.exit(1 if fails else 0)
