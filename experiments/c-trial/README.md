# C trial: the perk and scoring module in C (Calypsi 5.18)

This trial asks whether NOLFIED's game logic can be written in readable,
composable C and still run correctly and fast enough on a SNES.

## What's here

| File | Role |
| --- | --- |
| `perks.h` / `perks.c` | The perk deck. Each perk is a table entry (name, card text, max stacks, rarity) plus an optional `on_claim` hook. A hook is a one-line function that adds to the multiplier. To add a perk you add one entry and maybe one small function. |
| `score.h` / `score.c` | `claim_mult()` folds every owned perk's hook over a claim, and `claim_points()` returns chips × mult. It is the C version of `score_claim`'s arithmetic in `src/main.s`. |
| `bench.c`, `header.s` | Benchmark ROM: scores 40 shared scenarios (`gen_vectors.py`) and times each call with the PPU H/V counters. |
| `../../tools/bench_score.py` | Runs this ROM and the assembly `BENCH` build of the real game (`make bench` from the repo root). It checks both against an independent Python model and compares timings. |

Building needs the Calypsi 65816 toolchain (`calypsi-65816` 5.18 `.deb` from
https://www.calypsi.cc). It is free for hobby use, closed source.

## Results

```
OK: 40/40 scenarios match the model in both ROMs
mean per claim: C 1063.5 us, asm arithmetic 2031.6 us
one frame is 16639 us; a claim happens at most once per cut
```

- **Correctness:** C and assembly agree with the model in every scenario, but only
  after working around a compiler bug (below).
- **Speed:**
  - With small multipliers C is about 2x slower than the assembly (≈0.75 ms against ≈0.37 ms).
  - With big multipliers C is much faster (1.5 ms against 15 ms), because the assembly
    builds the product by repeated BCD addition and C uses a real multiply.
  - Either way, a claim costs at most a tenth of a frame, once per cut.
- **Size:** about even. The C hooks and `claim_mult` come to 445 bytes of code
  plus the 240-byte perk table. The assembly arithmetic is about the same once
  its tables are included.

## The compiler bug

With `--target=SNES`, Calypsi 5.18 wraps each 8x8 hardware multiply
(`$4202`/`$4203`) in `php` / `sei`. The `php` pushes a byte, but the following
stack-relative load of a stack argument isn't adjusted, so it reads the wrong
byte:

```c
typedef struct { uint16_t a; uint8_t b; } s_t;
void mul_arg(const s_t *p, uint8_t n, uint16_t *out) { *out += (uint16_t)p->b * n; }
```
```
php
sei
sep  #32
sta  0x4202
lda  5,s        ; n is at 6,s after the php
sta  0x4203
```

This trial showed it as CHAIN and PRISM returning `value × 0x84` instead of
`value × stacks`. `--no-ppu-mul` doesn't help. Compiling **without**
`--target=SNES` gives a correct software multiply. This trial does that, and
generic 65816 code runs fine on the SNES. Worth reporting upstream.

## Verdict

C delivers the readability: the whole scoring rule is `score.c` plus one-line
hooks, instead of about 150 lines of width-switching assembly. Speed is fine for
game logic.

The bug is the cautionary part. The tests caught a miscompile on the first run,
so a port has to keep the C side under the same tests the assembly has: the
scoring model, the flow test and the fuzzers.
