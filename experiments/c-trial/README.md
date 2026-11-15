# C trial: the perk and scoring module in C (Calypsi 5.18)

This trial asks whether NOLFIED's game logic can be written in readable,
composable C and still run correctly and fast enough on a SNES.

## What's here

| File | Role |
| --- | --- |
| `perk_defs.h` | **The deck.** One row per perk: id, card text, max stacks, rarity and, for scoring perks, its effect on the multiplier. The other files generate the enum, the card table and the scoring code from it (the X-macro idiom). |
| `perks.h` / `perks.c` | Types, the card table, and the **loadout**: the owned perks, with the scoring ones listed for fast iteration. |
| `score.h` / `score.c` | `claim_mult()` applies each owned scoring perk's effect, and `claim_points()` returns chips × mult. It is the C version of `score_claim`'s arithmetic in `src/main.s`. |
| `hw_math.h` | The SNES hardware multiplier, wrapped: `hw_mul8()`, `mul16x8()`, `mul16x16()`. |
| `bench.c`, `header.s` | Benchmark ROM: scores 40 shared scenarios (`gen_vectors.py`) and times each call with the PPU H/V counters. |
| `../../tools/bench_score.py` | Runs this ROM and the assembly `BENCH` build of the real game (`make bench` from the repo root). It checks both against an independent Python model and compares timings. |

Building needs the Calypsi 65816 toolchain (`calypsi-65816` 5.18 `.deb` from
https://www.calypsi.cc). It is free for hobby use, closed source.

## Results

The final benchmark output (`make bench` from the repo root). Each ROM's
empty-window timing cost is subtracted first.

```
mean per claim: C 480.7 us, asm arithmetic 2011.4 us
C / asm-arithmetic time: best 0.06x, median 0.38x, worst 0.95x; C slower in 0/40 scenarios
OK: 40/40 scenarios match the model in both ROMs
```

The C version is **at least as fast as the assembly in every scenario**:
- Fewest perks: up to 0.95× the assembly's time.
- Typical claims: about 0.4×.
- Large multipliers: 0.06×, because the assembly builds the product by repeated
  BCD addition.

### Getting there

Mean time per claim, worst-case ratio against the assembly, and number of
scenarios out of 40 where C was slower:

| Step | Change | Mean | Worst | Slower in |
| --- | --- | --- | --- | --- |
| 0 | First version: a 16-perk table of `{text, …, hook}`, scanned on every claim | 1063 µs | 2.24× | 17 |
| – | `-O2 --speed` / `--always-inline` | ±0 | ±0 | – |
| 1 | **Loadout:** iterate only owned scoring perks, rebuilt when a perk is taken; hot scoring data split from cold card text | 661 µs | 1.34× | 3 |
| 2 | **`hw_math.h`:** drive the 8×8 hardware multiplier explicitly | 594 µs | 1.15× | 3 |
| – | Benchmark fix: subtract each harness's own timing cost (C 77 µs, asm 24 µs) | 514 µs | 1.03× | 1 |
| 3 | 32-bit products assembled in 16-bit halves (no shift loops) | 489 µs | 1.03× | 1 |
| 4 | **X-macro deck:** a dense `switch` instead of function pointers | **481 µs** | **0.95×** | **0** |

Two variants of step 4 were tried and rejected:
- Leaving passive perks in the loop: 595 µs, worst 1.36×.
- A sparse `switch` with only the scoring cases: 721 µs, worst 1.44×, because it
  loses the jump table.

### What makes Calypsi C fast on the 65816

1. **Don't index arrays of odd-sized structs in hot loops.** A 15-byte struct
   costs a shift-and-subtract multiply per access. Split hot fields from cold ones.
2. **Do the work when state changes, not every frame.** A list of what you own,
   rebuilt when a perk is taken, beats scanning the deck on every claim.
3. **Function pointers are expensive:** about 220 cycles per call, including the
   runtime `_JmpInd` and the argument frame. A dense `switch` compiles to a jump
   table, but only while the cases are dense.
4. **Use the hardware multiplier by hand.** `hw_mul8()` must be a macro, because
   Calypsi won't inline a function that touches volatile registers, even with
   `--always-inline`. Put each product in its own statement: the operands of `+`
   are unsequenced in C, and two multiplies in one expression really did
   interleave their register writes and give wrong results.
5. **Avoid 32-bit shifts.** `x << 8` on a `uint32_t` is an 8-step loop; on a
   `uint16_t` it is `xba; and`.
6. **Measure.** Optimizer flags and `uint_fast8_t` made no measurable
   difference here. The data layout and the dispatch method made all of it.

## Legibility

Scoring, side by side. Everything you need to read to understand it, or edit to
add a scoring perk:

| | Assembly (`src/main.s`) | C (this directory) |
| --- | --- | --- |
| The scoring rule | `score_claim` arithmetic plus `mul8`, `add_plus`, `add_prod`, `bin2bcd`: **207 code lines, 21 register-width switches** | `score.c`: **32 lines**, plus one effect per scoring perk |
| A perk's definition | Spread across 7 places: `P_*` constant, `perk_max`, `perk_rar`, `perk_weight`, `perk_txt`, the card strings, and a block in `score_claim` | **One row** in `perk_defs.h` |
| Hardware detail | Everywhere | `hw_math.h` (33 lines), behind `hw_mul8()` / `mul16x16()` |

The same perk in each:

```asm
        A16                      ; SNIPER: +6 mult per stack on claims < 40 cells
        lda newly
        cmp #40
        A8
        bcs :+
        lda PERKS+P_SNIPER
        sta M_A
        lda #6
        sta M_B
        jsr mul8
        jsr add_plus
:
```
```c
SCORING(SNIPER, "SNIPER", "+6 MULT", "ON TINY", "CLAIMS", "(<40)", 5, COMMON,
        if (c->chips < TINY_CLAIM) m.plus += 6 * n)
```

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

C delivers both readability and speed. The whole scoring rule is `score.c` plus
one-line deck rows, against 207 lines of width-switching assembly, and it runs at
least as fast as the assembly in every scenario. Getting there took deliberate,
measured data layout (see "What makes Calypsi C fast"), not compiler flags.

The bug is the cautionary part. The tests caught a miscompile on the first run,
so a port has to keep the C side under the same tests the assembly has: the
scoring model, the flow test and the fuzzers.
