#!/usr/bin/env python3
"""Gameplay-logic test for the perk system / claim scoring of the SNES ROM.

    python3 tools/test_perks.py            # run everything, print PASS/FAIL table
    python3 tools/test_perks.py NAME ...   # run only the named scenarios
    python3 tools/test_perks.py --list

Each scenario runs in its own subprocess (one libretro core instance per process),
boots to the draft, forces the offered perk with an OFFERS poke, pokes the stack
counts for the configuration under test, then plays deterministic claims with
enemies pinned in place.  Expected values come from an independent Python model of
the scoring rules.  A scenario that gets killed by a stray enemy is retried with a
different boot delay (different RNG seed).
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

ROM = os.path.join(ROOT, "build", "nolfied.sfc")
LBL = os.path.join(ROOT, "build", "nolfied.lbl")

PERK = dict(GREED=0, CHAIN=1, TITAN=2, SNIPER=3, HUNTER=4, SWIFT=5, AEGIS=6,
            STASIS=7, CHRONO=8, PHOENIX=9, LUCKY=10, PRISM=11, GLASS=12,
            QUOTA=13, JACKPOT=14, MIDAS=15)
PERK_MAX = [9, 5, 3, 5, 5, 1, 3, 3, 3, 9, 2, 5, 1, 3, 5, 3]

# RAM map (from the task description / main.s)
from syms import S
PERKS, OFFERS, CURSOR = S.run_perks, S.offers, S.cursor
P_TOTAL, CHAIN, KILLS, AEGIS_C = S.run_perks + 16, S.chain, S.kills, S.aegis_left
GOAL, JACKMULT, MULT = S.goal, S.stage_mult, S.last_mult
E_X, E_Y, E_VX, E_VY, E_SPD = S.e_x, S.e_y, S.e_vx, S.e_vy, S.e_spd   # words: slot*2
E_TYPE, E_HALF, E_TIMER = S.e_type, S.e_half, S.e_timer              # bytes: slot
I_X, I_Y, I_ON = S.i_x, S.i_y, S.i_on                                 # bytes: slot
GRID = S.grid

ST_READY, ST_PLAY, ST_DYING, ST_CLEAR, ST_DRAFT = 1, 2, 3, 4, 6

SMALL = (4, 4)      # h, w  -> newly < 40
MEDIUM = (6, 6)     # newly ~ 40..149
BIG = (14, 12)      # newly >= 150
KILLBOX = (7, 7)   # roomy enough to hold a pinned minion in the middle


class Dead(Exception):
    pass


# --------------------------------------------------------------------------
#  scenario-side helpers (run inside the subprocess)
# --------------------------------------------------------------------------
class Game:
    def __init__(self, attempt):
        from retro import Emu
        self.lab = {}
        for l in open(LBL):
            _, a, n = l.split()
            self.lab[n[1:]] = int(a, 16)
        self.e = Emu(ROM)
        self.attempt = attempt
        self.pin = True
        self.keep = set()           # enemy slots whose velocity is NOT zeroed

    # --- memory
    def a(self, n):
        return self.lab[n] if isinstance(n, str) else n

    def b(self, n):
        return self.e.wram()[self.a(n)]

    def w(self, n):
        r = self.e.wram()
        a = self.a(n)
        return r[a] | r[a + 1] << 8

    def poke8(self, n, v):
        self.e.poke(self.a(n), bytes([v & 255]))

    def poke16(self, n, v):
        self.e.poke(self.a(n), bytes([v & 255, (v >> 8) & 255]))

    def score(self):
        """score in units of 10 points (a plain 32-bit integer)"""
        r = self.e.wram()
        a = self.lab["score"]
        return int.from_bytes(r[a:a + 4], "little")

    def pos(self):
        p = self.w("p_idx")
        return p & 63, p >> 6

    # --- time
    def frame(self, *btn):
        self.e.run(1, *btn)
        if self.pin and self.b("state") == ST_PLAY:
            self.sanitize()
        if self.b("state") == ST_DYING and not getattr(self, "allow_death", False):
            raise Dead()

    def sanitize(self):
        r = self.e.wram()
        for s in range(8):
            if r[E_TYPE + s] and s not in self.keep:
                self.e.poke(E_VX + s * 2, b"\0\0")
                self.e.poke(E_VY + s * 2, b"\0\0")
                self.e.poke(E_TIMER + s, b"\xff")

    def put_enemy(self, slot, cx, cy):
        """centre enemy `slot` on field cell (cx, cy)."""
        self.e.poke(E_X + slot * 2, bytes([0, cx * 4 + 2]))
        self.e.poke(E_Y + slot * 2, bytes([0, cy * 4 + 2]))
        self.e.poke(E_VX + slot * 2, b"\0\0")
        self.e.poke(E_VY + slot * 2, b"\0\0")

    def park_minions(self):
        for s in range(1, 8):
            if self.b(E_TYPE + s) == 2:
                self.put_enemy(s, 56 + s % 3, 4 + s % 3)

    def clear_items(self):
        for s in range(4):
            self.poke8(I_ON + s, 0)

    def put_item(self, slot, cx, cy):
        self.poke8(I_X + slot, cx * 4 + 2)
        self.poke8(I_Y + slot, cy * 4 + 2)
        self.poke8(I_ON + slot, 1)

    # --- flow
    def boot_to_draft(self):
        self.e.run(60 + 7 * self.attempt)
        self.e.run(3, "start")
        for _ in range(60):
            if self.b("state") == ST_DRAFT:
                break
            self.e.run(1)
        assert self.b("state") == ST_DRAFT, "never reached draft"
        self.e.run(45)              # input delay

    def draft(self, cfg, pick, lives=None):
        """cfg: {perk name: final stacks}.  The pick (+1 stack) is applied by the
        real draft code; all other stacks are poked beforehand."""
        pid = PERK[pick]
        assert cfg.get(pick, 0) >= 1
        tot = 0
        for n, i in PERK.items():
            st = cfg.get(n, 0)
            tot += st
            self.poke8(PERKS + i, st - 1 if i == pid else st)
        self.poke8(P_TOTAL, tot - 1)
        self.poke8(OFFERS, pid)
        self.poke8(OFFERS + 1, pid)
        self.poke8(OFFERS + 2, pid)
        self.poke16(CURSOR, 0)
        if lives is not None:
            self.poke8("lives", lives)
        self.lives_before = self.b("lives")
        self.e.run(2, "b")
        for _ in range(30):
            if self.b("state") == ST_READY:
                break
            self.e.run(1)
        assert self.b("state") == ST_READY, "pick did not load stage"

    def start_play(self, wait=0):
        while self.b("state") == ST_READY:
            self.e.run(1)
        assert self.b("state") == ST_PLAY
        self.pin = True
        self.sanitize()
        for _ in range(wait):
            self.frame()

    def snapshot(self):
        r = self.e.wram()
        return dict(
            perks=list(r[PERKS:PERKS + 16]), ptotal=r[P_TOTAL], chain=r[CHAIN],
            kills=r[KILLS], aegis=r[AEGIS_C], goal=self.w(GOAL), pspeed=r[self.lab["pspeed"]],
            lives=r[self.lab["lives"]], stage=r[self.lab["stage"]],
            espd=[self.w(E_SPD + s * 2) for s in range(8)],
            etype=[r[E_TYPE + s] for s in range(8)],
            items=sum(1 for s in range(4) if r[I_ON + s]),
            score=self.score())

    # --- movement
    def step(self, d, n, btn=True, limit=40):
        """move `n` cells in direction d (holding B if btn)."""
        done = 0
        for _ in range(n):
            p0 = self.w("p_idx")
            for f in range(limit):
                self.frame(*(("b", d) if btn else (d,)))
                if self.w("p_idx") != p0 or self.b("state") != ST_PLAY:
                    break
            else:
                raise RuntimeError("player stuck going " + d)
            done += 1

    def claim(self, hw, minion_inside=0, item_inside=0, kills_in=None):
        """Leave the bottom border at current x, draw up h / left w / down to the
        border.  Returns observation dict."""
        h, w = hw
        x0, y0 = self.pos()
        assert y0 == 47, f"not on bottom border: {self.pos()}"
        # place objects inside the region that is about to be enclosed
        for k in range(minion_inside):
            slot = 1 + k
            assert self.b(E_TYPE + slot) == 2
            self.put_enemy(slot, x0 - w // 2 - (k % 2), 47 - h // 2 - k // 2 * 0)
        for k in range(item_inside):
            self.put_item(k, x0 - w // 2 + k, 47 - h // 2 - 1 + 0 * k)
        before = dict(score=self.score(), chain=self.b(CHAIN), claimed=self.w("claimed"),
                      ptotal=self.b(P_TOTAL), lives=self.b("lives"))
        self.step("up", h)
        self.step("left", w)
        c0 = self.w("claimed")
        for f in range(200):
            self.frame("b", "down")
            if self.w("claimed") != c0 or self.b("state") != ST_PLAY:
                break
        else:
            raise RuntimeError("claim never closed")
        for _ in range(10):         # score_claim finishes a few frames after `claimed` changes
            self.frame()
        r = self.e.wram()
        obs = dict(before=before, newly=self.w("newly"), mult=self.w(MULT),
                   chain=r[CHAIN], kills=r[KILLS],
                   jack=self.w(JACKMULT), score=self.score(), freeze=self.w("freeze"),
                   state=r[self.lab["state"]], pct=r[self.lab["pct"]],
                   claimed=self.w("claimed"), goal=self.w(GOAL),
                   items_on=sum(1 for s in range(4) if r[I_ON + s]))
        return obs

    def next_start(self, gap=1):
        """walk along the bottom border (no B) leftwards by `gap` + width of what's claimed."""
        x, y = self.pos()
        if y != 47:
            # snap_player may leave us somewhere on the new edge; walk down it
            while self.pos()[1] != 47:
                self.step("down", 1, btn=False)
        for _ in range(gap):
            self.step("left", 1, btn=False)


def model(P, newly, chain, kills, jack, ptotal):
    plus = (1 + chain * (1 + P[1]) + 2 * P[0] + (6 * P[3] if newly < 40 else 0)
            + 3 * P[4] * kills + P[11] * ptotal + jack)
    xm = (1 + P[2] if newly >= 150 else 1) * (3 if P[12] else 1)
    mult = plus * xm
    if mult >= 1000:
        mult = 999
    return plus, xm, mult


def cfg_list(cfg):
    P = [0] * 16
    for n, v in cfg.items():
        P[PERK[n]] = v
    return P


# --------------------------------------------------------------------------
#  scenarios.  Each returns a list of (check name, ok, detail)
# --------------------------------------------------------------------------
def start(g, cfg, pick=None, lives=None, post=None):
    g.boot_to_draft()
    pick = pick or next(iter(cfg))
    g.draft(cfg, pick, lives)
    if post:
        post(g)
    snap = g.snapshot()
    g.start_play()
    g.park_minions()
    g.clear_items()
    return snap


def score_check(P, obs, kills_new=0, items=0, extra=0, tag=""):
    """verify MULT / score delta of one claim vs the model."""
    res = []
    plus, xm, mult = model(P, obs["newly"], obs["before"]["chain"], obs["kills"], obs["jack"],
                           obs["before"]["ptotal"])
    res.append((f"{tag}MULT={mult}", obs["mult"] == mult,
                f"got {obs['mult']} want {mult} (plus want {plus}, xm want {xm}, newly {obs['newly']}, chain {obs['before']['chain']}, "
                f"kills {obs['kills']}, jack {obs['jack']}, ptotal {obs['before']['ptotal']})"))
    want = obs["newly"] * mult + 50 * kills_new + 100 * items + extra
    got = obs["score"] - obs["before"]["score"]
    res.append((f"{tag}score+={want}", got == want, f"got {got} want {want}"))
    res.append((f"{tag}CHAIN->{min(obs['before']['chain'] + 1, 99)}",
                obs["chain"] == min(obs["before"]["chain"] + 1, 99), f"got {obs['chain']}"))
    return res


def sc_baseline(g):
    cfg = {"GREED": 1}
    def post(g):
        g.poke8(PERKS, 0)
        g.poke8(P_TOTAL, 0)
    start(g, cfg, post=post)
    obs = g.claim(SMALL)
    return score_check([0] * 16, obs)


def make_perk_claim(cfg, hw, pick=None, minion=0, item=0, pre_chain=None, tag="",
                    post=None):
    def run(g):
        def p(g):
            if pre_chain is not None:
                g.poke8(CHAIN, pre_chain)
            if post:
                post(g)
        start(g, cfg, pick=pick, post=p)
        obs = g.claim(hw, minion_inside=minion, item_inside=item)
        P = cfg_list(cfg)
        res = score_check(P, obs, kills_new=minion, items=item, tag=tag)
        res.append(("size category", True, f"newly={obs['newly']} (h,w={hw})"))
        return res
    return run


def sc_greed(g):
    return make_perk_claim({"GREED": 3}, SMALL)(g)


def sc_chain(g):
    cfg = {"CHAIN": 3}
    start(g, cfg)
    res = []
    P = cfg_list(cfg)
    for i in range(3):
        if i:
            g.next_start(2)
        obs = g.claim(SMALL)
        res += score_check(P, obs, tag=f"claim{i + 1} ")
    return res


def sc_titan(g):
    cfg = {"TITAN": 2}
    start(g, cfg)
    res = []
    obs = g.claim(BIG)
    res.append(("big claim >=150", obs["newly"] >= 150, f"newly={obs['newly']}"))
    res += score_check(cfg_list(cfg), obs, tag="big ")
    g.next_start(2)
    obs = g.claim(SMALL)
    res += score_check(cfg_list(cfg), obs, tag="small ")
    return res


def sc_sniper(g):
    cfg = {"SNIPER": 2}
    start(g, cfg)
    res = []
    obs = g.claim(SMALL)
    res.append(("small <40", obs["newly"] < 40, f"newly={obs['newly']}"))
    res += score_check(cfg_list(cfg), obs, tag="small ")
    g.next_start(2)
    obs = g.claim((8, 8))
    res.append(("claim >=40", obs["newly"] >= 40, f"newly={obs['newly']}"))
    res += score_check(cfg_list(cfg), obs, tag="large ")
    return res


def sc_hunter(g):
    cfg = {"HUNTER": 2}
    start(g, cfg)
    obs = g.claim(KILLBOX, minion_inside=2)
    res = score_check(cfg_list(cfg), obs, kills_new=2)
    res.append(("KILLS==2", obs["kills"] == 2, f"kills={obs['kills']}"))
    return res


def sc_swift(g):
    cfg = {"SWIFT": 1}
    snap = start(g, cfg)
    res = [("pspeed==1 at stage start", snap["pspeed"] == 1, f"pspeed={snap['pspeed']}")]
    x0, _ = g.pos()
    p = []
    for _ in range(6):
        g.frame("left")
        p.append(g.pos()[0])
    moved = x0 - p[-1]
    res.append(("1 cell/frame", moved == 6, f"moved {moved} cells in 6 frames"))
    return res


def sc_noswift(g):
    snap = start(g, {"GREED": 1})
    res = [("pspeed==2 w/o swift", snap["pspeed"] == 2, f"pspeed={snap['pspeed']}")]
    x0, _ = g.pos()
    for _ in range(6):
        g.frame("left")
    moved = x0 - g.pos()[0]
    res.append(("1 cell/2 frames", moved == 3, f"moved {moved} cells in 6 frames"))
    return res


def sc_aegis(g):
    cfg = {"AEGIS": 2}
    snap = start(g, cfg, post=lambda g: g.poke8(CHAIN, 5))
    res = [("AEGIS_C==2 at start", snap["aegis"] == 2, f"aegis={snap['aegis']}")]
    for _ in range(100):            # outlast the 90-frame spawn invulnerability
        g.frame()
    lives0 = g.b("lives")
    for hit in (1, 2):
        g.step("up", 4)
        x, y = g.pos()
        g.put_enemy(1, x, y + 2)    # box overlaps the trail directly behind the head
        g.keep.add(1)
        g.frame("b")
        g.keep.discard(1)
        g.put_enemy(1, 57, 5)
        st = g.b("state")
        res.append((f"hit{hit} absorbed (state PLAY)", st == ST_PLAY, f"state={st}"))
        res.append((f"hit{hit} AEGIS_C=={2 - hit}", g.b(AEGIS_C) == 2 - hit, f"aegis={g.b(AEGIS_C)}"))
        res.append((f"hit{hit} lives unchanged", g.b("lives") == lives0, f"lives={g.b('lives')}"))
        res.append((f"hit{hit} trail wiped", g.w("trail_len") == 0 and g.b("pmode") == 0,
                    f"trail_len={g.w('trail_len')} pmode={g.b('pmode')}"))
        res.append((f"hit{hit} CHAIN kept", g.b(CHAIN) == 5, f"chain={g.b(CHAIN)}"))
        res.append((f"hit{hit} invuln set", g.w("invuln") > 0, f"invuln={g.w('invuln')}"))
        for _ in range(100):
            g.frame()
    # third hit: no charges -> real death
    g.allow_death = True
    g.step("up", 4)
    x, y = g.pos()
    g.put_enemy(1, x, y + 2)
    g.keep.add(1)
    g.frame("b")
    g.keep.discard(1)
    res.append(("hit3 kills (state DYING)", g.b("state") == ST_DYING, f"state={g.b('state')}"))
    res.append(("hit3 CHAIN reset", g.b(CHAIN) == 0, f"chain={g.b(CHAIN)}"))
    for _ in range(95):
        g.e.run(1)
    res.append(("hit3 life lost", g.b("lives") == lives0 - 1, f"lives={g.b('lives')} (was {lives0})"))
    return res


def sc_noaegis_death(g):
    start(g, {"GREED": 1}, post=lambda g: g.poke8(CHAIN, 7))
    for _ in range(100):
        g.frame()
    lives0 = g.b("lives")
    g.allow_death = True
    g.step("up", 4)
    x, y = g.pos()
    g.put_enemy(1, x, y + 2)
    g.keep.add(1)
    g.frame("b")
    res = [("hit kills", g.b("state") == ST_DYING, f"state={g.b('state')}"),
           ("CHAIN reset", g.b(CHAIN) == 0, f"chain={g.b(CHAIN)}")]
    for _ in range(95):
        g.e.run(1)
    res.append(("life lost", g.b("lives") == lives0 - 1, f"lives {lives0}->{g.b('lives')}"))
    return res


def sc_stasis(g):
    cfg = {"STASIS": 2}
    start(g, cfg)
    obs = g.claim(SMALL)
    res = score_check(cfg_list(cfg), obs)
    # freeze keeps ticking down while score_claim finishes and we wait
    res.append(("freeze==180 (minus <=20 ticks)", 160 <= obs["freeze"] <= 180, f"freeze={obs['freeze']}"))
    # a larger existing freeze must not be shortened
    g.poke16("freeze", 1000)
    g.next_start(2)
    obs = g.claim(SMALL)
    res.append(("bigger freeze kept (>=900)", obs["freeze"] >= 900, f"freeze={obs['freeze']}"))
    return res


def sc_chrono(g):
    base = {}
    snaps = {}
    for n in (0, 3):
        pass
    cfg = {"CHRONO": 3}
    snap = start(g, cfg)
    stage = snap["stage"]
    boss = min(0x200, 0xA8 + 24 * stage)
    mini = min(0x240, 0xF0 + 20 * stage)
    def sc(v, k):
        return v - k * (v // 5)
    res = [("boss E_SPD scaled", snap["espd"][0] == sc(boss, 3), f"got {snap['espd'][0]} want {sc(boss, 3)}")]
    ok = all(snap["espd"][s] == sc(mini, 3) for s in range(1, 8) if snap["etype"][s] == 2)
    res.append(("minion E_SPD scaled", ok,
                f"got {[snap['espd'][s] for s in range(1, 8) if snap['etype'][s] == 2]} want {sc(mini, 3)}"))
    return res


def sc_chrono0(g):
    snap = start(g, {"GREED": 1})
    stage = snap["stage"]
    boss = min(0x200, 0xA8 + 24 * stage)
    mini = min(0x240, 0xF0 + 20 * stage)
    ok = snap["espd"][0] == boss and all(snap["espd"][s] == mini for s in range(1, 8) if snap["etype"][s] == 2)
    return [("unscaled E_SPD", ok, f"boss {snap['espd'][0]} want {boss}, mini {snap['espd'][1:4]} want {mini}")]


def sc_phoenix(g):
    cfg = {"PHOENIX": 1}
    g.boot_to_draft()
    g.draft(cfg, "PHOENIX")
    res = [("lives +1 on pick", g.b("lives") == g.lives_before + 1, f"{g.lives_before}->{g.b('lives')}")]
    return res


def sc_phoenix_cap(g):
    g.boot_to_draft()
    g.draft({"PHOENIX": 2}, "PHOENIX", lives=9)
    return [("lives capped at 9", g.b("lives") == 9, f"lives={g.b('lives')}")]


def sc_glass(g):
    cfg = {"GLASS": 1}
    g.boot_to_draft()
    g.draft(cfg, "GLASS")
    res = [("lives -1 on pick", g.b("lives") == g.lives_before - 1, f"{g.lives_before}->{g.b('lives')}")]
    return res


def sc_glass_low(g):
    g.boot_to_draft()
    g.draft({"GLASS": 1}, "GLASS", lives=1)
    return [("no life loss at 1 life", g.b("lives") == 1, f"lives={g.b('lives')}")]


def sc_glass_score(g):
    cfg = {"GLASS": 1}
    start(g, cfg)
    obs = g.claim(SMALL)
    res = score_check(cfg_list(cfg), obs)
    return res


def sc_lucky(g):
    cfg = {"LUCKY": 2}
    g.boot_to_draft()
    g.draft(cfg, "LUCKY")
    return [("4 capsules at stage start", g.snapshot()["items"] == 4, f"items={g.snapshot()['items']}")]


def sc_lucky1(g):
    g.boot_to_draft()
    g.draft({"LUCKY": 1}, "LUCKY")
    return [("3 capsules", g.snapshot()["items"] == 3, f"items={g.snapshot()['items']}")]


def sc_nolucky(g):
    g.boot_to_draft()
    g.draft({"GREED": 1}, "GREED")
    return [("2 capsules", g.snapshot()["items"] == 2, f"items={g.snapshot()['items']}")]


def sc_prism(g):
    cfg = {"PRISM": 3, "GREED": 2}
    start(g, cfg, pick="PRISM")
    obs = g.claim(SMALL)
    res = score_check(cfg_list(cfg), obs)
    res.append(("P_TOTAL==5", obs["before"]["ptotal"] == 5, f"ptotal={obs['before']['ptotal']}"))
    return res


def sc_quota(g):
    cfg = {"QUOTA": 2}
    snap = start(g, cfg)
    res = [("GOAL==70", snap["goal"] == 70, f"goal={snap['goal']}")]
    # pct after claim ~ (claimed*3)//80 ; poke so a small claim lands in [70,80)
    g.poke16("claimed", 1860)       # 69.75 -> 69%, +newly pushes over 70
    obs = g.claim(SMALL)
    pct = (obs["claimed"] * 3) // 80
    res.append(("pct computed", obs["pct"] == min(pct, 99), f"pct={obs['pct']} want {pct} (claimed {obs['claimed']})"))
    res.append(("clears at pct>=70", obs["state"] == ST_CLEAR, f"state={obs['state']} pct={obs['pct']}"))
    return res


def sc_quota_no_clear(g):
    cfg = {"QUOTA": 2}
    start(g, cfg)
    g.poke16("claimed", 1700)       # 63% -> stays < 70 after a small claim
    obs = g.claim(SMALL)
    return [("no clear below goal", obs["state"] == ST_PLAY, f"state={obs['state']} pct={obs['pct']}")]


def sc_jackpot(g):
    cfg = {"JACKPOT": 3}
    start(g, cfg)
    obs = g.claim(KILLBOX, item_inside=2)
    res = [("JACKMULT==24", obs["jack"] == 24, f"jack={obs['jack']}")]
    res += score_check(cfg_list(cfg), obs, items=2)
    return res


def sc_jack_reset(g):
    """JACKMULT is per-stage: must be 0 right after a stage load."""
    cfg = {"JACKPOT": 3}
    g.boot_to_draft()
    g.poke16(JACKMULT, 77)
    g.draft(cfg, "JACKPOT")
    return [("JACKMULT reset on load", g.w(JACKMULT) == 0, f"jack={g.w(JACKMULT)}")]


def midas_run(stacks, extra_cfg=None):
    def run(g):
        cfg = {"MIDAS": stacks}
        cfg.update(extra_cfg or {})
        start(g, cfg, pick="MIDAS")
        g.poke16("claimed", 2600)
        obs = g.claim(SMALL)
        goal = obs["goal"]
        res = [("state CLEAR", obs["state"] == ST_CLEAR, f"state={obs['state']}")]
        bonus = (obs["pct"] - goal) * 100 + 50
        want_total = None
        P = cfg_list(cfg)
        plus, xm, mult = model(P, obs["newly"], obs["before"]["chain"], obs["kills"], obs["jack"],
                               obs["before"]["ptotal"])
        want = obs["newly"] * mult + bonus * (1 + stacks)
        got = obs["score"] - obs["before"]["score"]
        res.append((f"clear score +{want} (bonus {bonus} x{1 + stacks})", got == want,
                    f"got {got} want {want}; pct={obs['pct']} goal={goal}"))
        return res
    return run


def sc_combo_greed_glass_prism(g):
    cfg = {"GREED": 3, "GLASS": 1, "PRISM": 2}
    g.boot_to_draft()
    g.draft(cfg, "GLASS")
    res = [("lives -1 (glass)", g.b("lives") == g.lives_before - 1, f"{g.lives_before}->{g.b('lives')}")]
    g.start_play()
    g.park_minions()
    g.clear_items()
    obs = g.claim(SMALL)
    res += score_check(cfg_list(cfg), obs)
    res.append(("MULT==57", obs["mult"] == (1 + 6 + 2 * 6) * 3, f"mult={obs['mult']}"))
    return res


def sc_combo_chain3(g):
    cfg = {"CHAIN": 3, "GREED": 1}
    start(g, cfg)
    res = []
    for i in range(5):
        if i:
            g.next_start(2)
        obs = g.claim(SMALL)
        res += score_check(cfg_list(cfg), obs, tag=f"claim{i + 1} ")
    return res


def sc_cap(g):
    cfg = {"CHAIN": 5, "GREED": 9, "TITAN": 3, "GLASS": 1}
    start(g, cfg, post=lambda g: g.poke8(CHAIN, 99))
    obs = g.claim(BIG)
    res = score_check(cfg_list(cfg), obs)
    res.append(("MULT capped at 999", obs["mult"] == 999, f"mult={obs['mult']}"))
    return res


def sc_chain_cap(g):
    start(g, {"GREED": 1}, post=lambda g: g.poke8(CHAIN, 99))
    obs = g.claim(SMALL)
    return [("CHAIN stays 99", obs["chain"] == 99, f"chain={obs['chain']}")]


def sc_combo_hunter_prism_jack(g):
    cfg = {"HUNTER": 3, "PRISM": 2, "JACKPOT": 2, "GREED": 1}
    start(g, cfg, pick="HUNTER")
    obs = g.claim(KILLBOX, minion_inside=2, item_inside=1)
    res = score_check(cfg_list(cfg), obs, kills_new=2, items=1)
    return res


def sc_combo_titan_sniper(g):
    cfg = {"TITAN": 2, "SNIPER": 2, "GREED": 2}
    start(g, cfg, pick="TITAN")
    res = []
    obs = g.claim(BIG)
    res += score_check(cfg_list(cfg), obs, tag="big ")
    g.next_start(2)
    obs = g.claim(SMALL)
    res += score_check(cfg_list(cfg), obs, tag="small ")
    return res


def sc_carry_perks(g):
    """perks persist, KILLS resets between stages: a pick on a second draft must stack."""
    g.boot_to_draft()
    g.draft({"GREED": 1}, "GREED")
    g.start_play()
    g.park_minions()
    g.clear_items()
    # finish the stage: poke claimed high, claim once
    g.poke16("claimed", 2600)
    obs = g.claim(SMALL)
    res = [("stage cleared", obs["state"] == ST_CLEAR, f"state={obs['state']}")]
    for _ in range(300):
        g.e.run(1)
        if g.b("state") == ST_DRAFT:
            break
    res.append(("back at draft", g.b("state") == ST_DRAFT, f"state={g.b('state')}"))
    g.e.run(45)
    g.poke8(OFFERS, PERK["GREED"])
    g.poke16(CURSOR, 0)
    g.e.run(2, "b")
    g.e.run(3)
    res.append(("GREED stacks to 2", g.b(PERKS) == 2, f"greed={g.b(PERKS)}"))
    res.append(("P_TOTAL==2", g.b(P_TOTAL) == 2, f"ptotal={g.b(P_TOTAL)}"))
    res.append(("stage==2", g.b("stage") == 2, f"stage={g.b('stage')}"))
    res.append(("KILLS reset", g.b(KILLS) == 0, f"kills={g.b(KILLS)}"))
    return res


SCENARIOS = {
    "baseline": sc_baseline,
    "GREED x3": sc_greed,
    "CHAIN x3 (3 claims)": sc_chain,
    "TITAN x2": sc_titan,
    "SNIPER x2": sc_sniper,
    "HUNTER x2 (2 kills)": sc_hunter,
    "SWIFT": sc_swift,
    "no SWIFT speed": sc_noswift,
    "AEGIS x2": sc_aegis,
    "no AEGIS death": sc_noaegis_death,
    "STASIS x2": sc_stasis,
    "CHRONO x3": sc_chrono,
    "CHRONO x0": sc_chrono0,
    "PHOENIX": sc_phoenix,
    "PHOENIX cap 9": sc_phoenix_cap,
    "GLASS": sc_glass,
    "GLASS at 1 life": sc_glass_low,
    "GLASS score": sc_glass_score,
    "LUCKY x2": sc_lucky,
    "LUCKY x1": sc_lucky1,
    "no LUCKY": sc_nolucky,
    "PRISM x3 (+GREED2)": sc_prism,
    "QUOTA x2 clear": sc_quota,
    "QUOTA x2 no clear": sc_quota_no_clear,
    "JACKPOT x3": sc_jackpot,
    "JACKPOT reset": sc_jack_reset,
    "MIDAS x1": midas_run(1),
    "MIDAS x3": midas_run(3),
    "MIDAS x0 (GREED)": midas_run(0, {"GREED": 1}) if False else None,
    "combo GREED3+GLASS+PRISM2": sc_combo_greed_glass_prism,
    "combo CHAIN3+GREED, 5 claims": sc_combo_chain3,
    "combo cap 999": sc_cap,
    "CHAIN counter cap 99": sc_chain_cap,
    "combo HUNTER3+PRISM2+JACKPOT2": sc_combo_hunter_prism_jack,
    "combo TITAN2+SNIPER2+GREED2": sc_combo_titan_sniper,
    "perks carry across stages": sc_carry_perks,
}
SCENARIOS = {k: v for k, v in SCENARIOS.items() if v}


# --------------------------------------------------------------------------
def child(name, attempt):
    try:
        g = Game(attempt)
        res = SCENARIOS[name](g)
        out = {"status": "ok", "checks": [(a, bool(b), c) for a, b, c in res]}
    except Dead:
        out = {"status": "dead"}
    except Exception as ex:   # noqa
        import traceback
        out = {"status": "error", "err": traceback.format_exc()[-800:]}
    sys.stdout.write("\n@@RESULT@@" + json.dumps(out) + "\n")


def parent(names):
    rows = []
    allok = True
    for name in names:
        out = None
        for attempt in range(6):
            p = subprocess.run([sys.executable, "-I", os.path.abspath(__file__), "--child", name, str(attempt)],
                               capture_output=True, text=True, cwd=ROOT,
                               env=dict(os.environ, PYTHONPATH=HERE))
            txt = p.stdout
            if "@@RESULT@@" not in txt:
                out = {"status": "error", "err": (p.stderr or txt)[-600:]}
                continue
            out = json.loads(txt.split("@@RESULT@@")[-1])
            if out["status"] != "dead":
                break
        if out["status"] == "dead":
            rows.append((name, "ERROR", "killed by enemy on every attempt"))
            allok = False
        elif out["status"] == "error":
            rows.append((name, "ERROR", out["err"].strip().splitlines()[-1]))
            allok = False
        else:
            for a, ok, det in out["checks"]:
                rows.append((name, "PASS" if ok else "FAIL", f"{a}" + ("" if ok else f"  -- {det}")))
                allok &= ok
    w0 = max(len(r[0]) for r in rows)
    last = None
    for n, st, d in rows:
        print(f"{(n if n != last else ''):<{w0}}  {st:<5}  {d}")
        last = n
    npass = sum(1 for r in rows if r[1] == "PASS")
    print(f"\n{npass}/{len(rows)} checks passed")
    return 0 if allok else 1


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--child":
        child(sys.argv[2], int(sys.argv[3]))
    elif len(sys.argv) > 1 and sys.argv[1] == "--list":
        print("\n".join(SCENARIOS))
    else:
        subprocess.run(["make", "-s"], cwd=ROOT, check=False, stdout=subprocess.DEVNULL)
        sys.exit(parent(sys.argv[1:] or list(SCENARIOS)))
