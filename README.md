# NOLFIED

A territory-claiming arcade game for the **Super Nintendo / Super Famicom**, in the
spirit of the old Qix / Volfied games. Cut lines through a force field to claim
territory and uncover the hidden picture underneath. Claim **80%** of the field to
clear the stage, and don't let anything touch your line while you're cutting.

![screenshots](docs/screenshots.png)

## Play it

The ready-to-run ROM is **[`dist/nolfied.sfc`](dist/nolfied.sfc)** (256KB HiROM, NTSC), also attached to each
[release](https://github.com/zmack/nolfied/releases) with checksums.
The original all-assembly build, which plays the same, is
[`dist/legacy/nolfied-asm.sfc`](dist/legacy/nolfied-asm.sfc) (256KB LoROM).

- **MAME:** `mame snes -cart dist/nolfied.sfc`. MAME needs its own `snes` BIOS set
  (the file `spc700.rom` in `snes.zip`) in your rompath, same as for any SNES game.
- **bsnes / higan / ares, Snes9x, Mesen, RetroArch:** open `nolfied.sfc` directly.
- It should also run from an SD-card flash cart on real hardware. It doesn't use any
  special chips or save RAM.

## Controls

| Button | Action |
| --- | --- |
| D-pad | Move along the edge of your claimed area |
| Hold **B** (or A / X / Y) + D-pad | Leave the edge and cut a line into open space |
| Let go of B while cutting | Your ship pulls back along the line to where it started |
| Start | Start the game / pause |
| Left / Right, B, Select (draft) | Pick a card, take it, reroll once |

## Rules

- When your line reaches an edge again, the area on the side **without the big
  eye-boss** is claimed and that part of the picture appears.
- If the boss or a star-shard touches your line, or touches you while you're cutting,
  you lose a life.
- Star-shards caught inside a claimed area are destroyed.
- **?** capsules you enclose give a random power-up: speed up, a 10s shield, freezing
  the enemies, or an extra life.
- There are four hidden pictures that repeat, and each stage adds speed and shards.

## Chips x Mult, chains and perks

Scoring works like Balatro:

- Every claim scores **chips x mult**. Chips are the number of cells you claimed. You
  see the sum pop up under the field, e.g. `220 X 12 = +26400`, and the screen
  shakes and flashes harder for bigger claims and bigger multipliers.
- **Chain:** each claim adds one link, and each link adds +1 mult. You lose the chain if
  you die, or if 10 seconds pass without a claim (the orange bar on the HUD).
- **Perk draft:** before every stage you pick **1 of 3 perk cards**. Perks stack, and
  you can reroll the offer once per draft with SELECT. Rarity sets the frame colour:
  common is blue, special is green and rare is pink. Your perks show along the top row.

| Perk | Rarity | Effect |
| --- | --- | --- |
| GREED | common | +2 mult on every claim |
| CHAIN | common | every chain link is worth +1 more mult |
| TITAN | special | x2 mult on claims of 150+ cells (x3, x4 when stacked) |
| SNIPER | common | +6 mult on claims under 40 cells |
| HUNTER | common | +3 mult per shard killed this stage |
| SWIFT | common | move faster |
| AEGIS | special | absorbs one hit per stage |
| STASIS | common | each claim freezes the enemies for 1.5s |
| CHRONO | special | enemies 20% slower |
| PHOENIX | special | +1 life |
| LUCKY | common | +1 capsule each stage |
| PRISM | rare | +1 mult for each perk you own |
| GLASS | rare | x3 mult, but costs a life |
| QUOTA | special | stage goal -5% |
| JACKPOT | common | each capsule gives +4 mult for the rest of the stage |
| MIDAS | special | x2 stage-clear bonus |

Some combinations work well together: SNIPER + CHAIN for lots of quick small claims,
TITAN + GLASS for a few huge cuts, or PRISM once you have a lot of perks.

## Building

The game logic is C, compiled with [Calypsi](https://github.com/hth313/Calypsi-tool-chains)
for the 65816 (5.18), on a small assembly core: boot, NMI, DMA uploads, the field
kernels (flood fill, redraw, box scan), text output and the SPC700 driver. Also
needs Python 3, Pillow and numpy; `ca65`/`ld65` (cc65) build the legacy ROM.

```sh
pip install pillow numpy
make            # -> build/nolfied.sfc (C)
make legacy     # -> build/legacy/nolfied.sfc (the original assembly)
```

- `src/game.h`: the module map and the contract between the C modules;
  `src/core.h`: what C may call in the assembly core (`src/core.s`).
- `docs/PORTING.md`: how the C port relates to `legacy/main.s`, the rules for
  writing fast C with Calypsi, and where performance stands.
- `tools/gen_assets.py`, `tools/gen_icons.py`: generate all the graphics (field
  tiles, font, logo, sprites, the four stage pictures, the perk icons) in code.
  `tools/gen_samples.py` does the same for the sound samples.
- `tools/record_demo.py OUT.mp4 [SECONDS] [SEED]`: records a gameplay video, with
  a bot playing.
- `tools/check_modes.py`: runs on every build and rejects the accumulator-width
  miscompiles Calypsi 5.18 is known to produce.
- `tools/retro.py`: a headless libretro host (uses the bsnes-mercury core:
  `apt install libretro-bsnes-mercury-accuracy`).
- `make test`: `tools/test_flow.py` walks every state transition, checks the
  runtime state-machine checker and the frame pacing. `tools/test_perks.py` checks
  each perk against an independent scoring model. `tools/test_selftest.py` runs
  the self-tests built into the profiling ROM (box scan and number printing
  against C models).
- `make verify-port`: the assembly core's routines that came from `legacy/main.s`
  must still match it byte for byte.
- `make profile`: per-stage CPU time of the C ROM against the legacy ROM.
- `tools/playtest.py OUT SEED STEPS`: a random-input soak test that checks the
  field and the state machines.
- `tools/fuzz_input.py SEED FRAMES`: a hostile-input fuzzer. It sends impossible
  D-pad combinations, all buttons at once, inputs that flip every frame,
  Start/Select mashing and button storms around state changes. It checks the
  state machines, the sound CPU, value ranges, hangs, stack depth and the field.
- Releases: add `.github/release-notes/vX.Y.Z.md` and push to main. The
  `release` workflow then publishes that version with the ROMs from `dist/`.
- `make tla`: model-checks the TLA+ specs in [`spec/`](spec/README.md). They cover
  the NMI/main-loop and SNES/SPC700 handshakes and the game state machine.

## Tech notes

- Mode 1. BG2 holds the stage picture and BG1 is the force field on top of it. Each
  BG1 tile is a 2x2 block of 4x4-pixel cells. Every combination of the four cell
  states (open / claimed / edge / line) has its own tile, which gives 256 tiles, so the
  field has a 60x48 grid while the map is still made of ordinary tiles.
- Claiming uses a flood fill from the boss's position. Anything it doesn't reach gets
  claimed, then the edge cells are worked out again.
- Sound: a 33-byte SPC700 program that writes DSP registers on request, with a
  READY handshake. The 65816 side sequences everything. The sound effects and
  jingles use voices 0-2. The in-game music (`src/music.c`) is dark synthpop in A
  minor at about 129 BPM, on voices 3-7. It has a plucked saw bass in octaves,
  saw-chord stabs, a drum machine with a metal "clank", and a pulse lead, with the
  DSP echo as an 8th-note delay. `tools/gen_samples.py` synthesises and BRR-encodes
  every instrument.
- Game flow and the player's mode are explicit state machines: a transition table,
  entry actions and a runtime checker. See `spec/README.md`.
