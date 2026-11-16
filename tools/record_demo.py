#!/usr/bin/env python3
"""Record a gameplay video: a bot plays the ROM, every frame goes to ffmpeg.

Usage: python3 tools/record_demo.py OUT.mp4 [SECONDS] [SEED]

The bot only reads what a player could see (the field, the player, the
enemies) from WRAM and presses buttons. Each time it stands on the edge it
picks a cut: straight or L-shaped lines from edge cells, scored by the area
the game would claim (a flood fill from the boss, as in field_fill) per cell
of travel, rejecting lines that pass near an enemy. While cutting, if an
enemy gets close it finishes the line or lets go of the button to pull the
trail back in, whichever is quicker.
"""
import os
import random
import subprocess
import sys
import wave
from collections import deque

sys.path.insert(0, os.path.dirname(__file__))
from retro import Emu  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "demo.mp4")
SECONDS = float(sys.argv[2]) if len(sys.argv) > 2 else 90
SEED = int(sys.argv[3]) if len(sys.argv) > 3 else 1
SCALE = 2

lab = {}
for line in open(os.path.join(ROOT, "build", "nolfied.lbl")):
    _, a, n = line.split()
    lab[n[1:]] = int(a, 16) & 0x1FFFF

W, H = 60, 48
OPEN, CLAIM, EDGE, TRAIL = 0, 1, 2, 3
DIRS = {"up": -64, "down": 64, "left": -1, "right": 1}
ST_TITLE, ST_READY, ST_PLAY, ST_DYING, ST_CLEAR, ST_OVER, ST_DRAFT = range(7)
rnd = random.Random(SEED)


def u16(m, a):
    return m[a] | m[a + 1] << 8


def cxy(c):
    return c & 63, c >> 6


def centre(c):
    x, y = cxy(c)
    return x * 4 + 2, y * 4 + 2


def enemies(m):
    out = []
    for s in range(8):
        if m[lab["e_type"] + s]:
            x = u16(m, lab["e_x"] + 2 * s) >> 8
            y = u16(m, lab["e_y"] + 2 * s) >> 8
            half = u16(m, lab["e_half"] + 2 * s)
            spd = u16(m, lab["e_spd"] + 2 * s) / 256
            out.append((x, y, half, spd, s == 0))
    return out


def in_field(c):
    x, y = cxy(c)
    return 0 <= x < W and 0 <= y < H


def neighbours(c):
    x, y = cxy(c)
    if x > 0:
        yield c - 1
    if x < W - 1:
        yield c + 1
    if y > 0:
        yield c - 64
    if y < H - 1:
        yield c + 64


def claim_gain(grid, cut, boss_cell):
    """cells the game would claim if `cut` (open cells) became a trail"""
    blocked = set(cut)
    seen = {boss_cell} if grid[boss_cell] == OPEN and boss_cell not in blocked else set()
    q = deque(seen)
    while q:
        c = q.popleft()
        for n in neighbours(c):
            if n not in seen and n not in blocked and grid[n] == OPEN:
                seen.add(n)
                q.append(n)
    total_open = sum(1 for v in grid if v == OPEN)
    return total_open - len(seen)


def edge_paths(grid, start):
    """shortest walk along edge cells from start: cell -> previous cell"""
    prev = {start: None}
    q = deque([start])
    while q:
        c = q.popleft()
        for n in neighbours(c):
            if n not in prev and grid[n] == EDGE:
                prev[n] = c
                q.append(n)
    return prev


def walk_to(prev, c):
    path = []
    while c is not None:
        path.append(c)
        c = prev[c]
    return path[::-1]


def ray(grid, c, d, limit):
    """open cells from c (exclusive) along d; returns (cells, end cell) where
    the end is the edge cell that closes the line, or None"""
    cells = []
    while len(cells) < limit:
        c += d
        if not in_field(c) or abs((c & 63) - ((c - d) & 63)) > 1:
            return cells, None
        if grid[c] == OPEN:
            cells.append(c)
        elif grid[c] == EDGE:
            return cells, c
        else:
            return cells, None
    return cells, None


def near(cells, foes, margin_boss, margin_shard):
    for (ex, ey, half, spd, boss) in foes:
        m = half + (margin_boss if boss else margin_shard)
        for c in cells:
            x, y = centre(c)
            if abs(x - ex) < m + 2 and abs(y - ey) < m + 2:
                return True
    return False


def plan(m):
    grid = m[lab["grid"]:lab["grid"] + 48 * 64]
    p = u16(m, lab["p_idx"])
    foes = enemies(m)
    if not foes or not foes[0][4]:
        return None
    bx, by = foes[0][0], foes[0][1]
    boss_cell = (by >> 2) * 64 + (bx >> 2)
    prev = edge_paths(grid, p)
    best, best_score = None, 0
    starts = [c for c in prev if len(walk_to(prev, c)) < 70]
    rnd.shuffle(starts)
    tried = 0
    for s in starts:
        for dname, d in DIRS.items():
            if not in_field(s + d) or grid[s + d] != OPEN:
                continue
            shapes = []
            cells, end = ray(grid, s, d, 40)
            if end is not None and cells:
                shapes.append(cells + [end])
            for depth in (3, 6, 10, 15):
                leg, e1 = ray(grid, s, d, depth)
                if len(leg) < depth or e1 is not None:
                    continue
                for t in ((-1, 1) if d in (64, -64) else (-64, 64)):
                    leg2, end2 = ray(grid, leg[-1], t, 45)
                    if end2 is not None:
                        shapes.append(leg + leg2 + [end2])
            for path in shapes:
                cut = path[:-1]
                if near(cut, foes, 22, 10):
                    continue
                tried += 1
                gain = claim_gain(grid, cut, boss_cell)
                travel = len(walk_to(prev, s))
                score = gain / (12 + travel + 2.5 * len(cut))
                if gain >= 12 and score > best_score:
                    best_score = score
                    best = walk_to(prev, s) + path
        if tried > 120:
            break
    return best


def direction(a, b):
    for name, d in DIRS.items():
        if a + d == b:
            return name
    return None


class Bot:
    def __init__(self):
        self.path = None
        self.cooldown = 0
        self.retreat = False
        self.draft_t = 0
        self.title_t = 0

    def buttons(self, m):
        st = m[lab["state"]]
        if st == ST_TITLE:                  # show the title for 3 s
            self.title_t += 1
            return ["start"] if self.title_t % 180 == 0 else []
        if st == ST_DRAFT:
            self.draft_t += 1
            if self.draft_t in (70, 100):
                return ["right"]
            if self.draft_t == 150:
                return ["b"]
            return []
        self.draft_t = 0
        if st == ST_OVER:
            return ["start"] if rnd.random() < 0.02 else []
        if st != ST_PLAY:
            self.path = None
            return []
        return self.play(m)

    def play(self, m):
        pmode = m[lab["pmode"]]
        p = u16(m, lab["p_idx"])
        if self.retreat:
            if pmode == 0:
                self.retreat = False
                self.path = None
                self.cooldown = 20
            return []                       # no button: the trail pulls back
        if pmode == 0 and (self.path is None or p not in self.path):
            if self.cooldown:
                self.cooldown -= 1
                return []
            self.path = plan(m)
            if self.path is None:
                self.cooldown = 10
                return []
        if self.path is None or p not in self.path:
            return ["b"] if pmode else []
        i = self.path.index(p)
        if i + 1 >= len(self.path):
            self.path = None
            return []
        nxt = self.path[i + 1]
        grid_next = m[lab["grid"] + nxt]
        cutting = pmode != 0 or grid_next == OPEN
        if pmode != 0 and self.danger(m, i):
            self.retreat = True
            return []
        d = direction(p, nxt)
        return ([d] if d else []) + (["b"] if cutting else [])

    def danger(self, m, i):
        """an enemy is about to reach the trail: finish or pull back"""
        trail = [c for c in self.path[:i + 1] if m[lab["grid"] + c] == TRAIL]
        remaining = len(self.path) - 1 - i
        spd_cells = m[lab["pspeed"]]
        t_finish = remaining * spd_cells
        t_back = (len(trail) + 1) // 2
        if t_finish <= t_back:
            return False                    # finishing is the way out
        foes = enemies(m)
        for (ex, ey, half, spd, boss) in foes:
            reach = half + 3 + spd * t_back * 1.4 + (6 if boss else 3)
            for c in trail + [self.path[i]]:
                x, y = centre(c)
                if abs(x - ex) < reach and abs(y - ey) < reach:
                    return True
        return False


def main():
    rom = os.path.join(ROOT, "build", "nolfied.sfc")
    e = Emu(rom)
    e.run(1)
    w, h = e.image().size
    tmp = OUT + ".video.mp4"
    ff = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", f"{w * SCALE}x{h * SCALE}", "-r", "60.0988", "-i", "-",
         "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p", tmp],
        stdin=subprocess.PIPE)
    bot = Bot()
    frames = int(SECONDS * 60)
    stats = {"claims": 0, "deaths": 0, "max_stage": 0}
    prev_state, prev_claimed = None, 0
    e.audio = bytearray()
    for f in range(frames):
        m = e.wram()
        e.run(1, *bot.buttons(m))
        im = e.image().resize((w * SCALE, h * SCALE), 0)
        ff.stdin.write(im.tobytes())
        m = e.wram()
        st = m[lab["state"]]
        if st == ST_DYING and prev_state != ST_DYING:
            stats["deaths"] += 1
        c = u16(m, lab["claimed"])
        if c > prev_claimed:
            stats["claims"] += 1
        prev_claimed = c
        prev_state = st
        stats["max_stage"] = max(stats["max_stage"], m[lab["stage"]])
        if f % 600 == 0:
            print(f"t={f / 60:5.1f}s state {st} stage {m[lab['stage']]} pct {m[lab['pct']]} "
                  f"lives {m[lab['lives']]}", flush=True)
    ff.stdin.close()
    ff.wait()
    wav = OUT + ".wav"
    with wave.open(wav, "wb") as wv:
        wv.setnchannels(2)
        wv.setsampwidth(2)
        wv.setframerate(32040)
        wv.writeframes(bytes(e.audio))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-i", wav,
                    "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", "-shortest", OUT], check=True)
    os.remove(tmp)
    os.remove(wav)
    print("wrote", OUT, stats)


main()
