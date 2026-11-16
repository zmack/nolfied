# Porting the game logic from legacy/main.s to C

The game is moving from all-assembly (`legacy/main.s`, ca65) to C (Calypsi
65816) with a small assembly core (`src/core.s`). **Behaviour must stay the
same**. The regression tests (`tools/test_flow.py`, `tools/test_perks.py`,
`tools/fuzz_input.py`, `tools/playtest.py`) and the TLA+ models (`spec/`)
describe that behaviour.

## Ground rules

1. **The contract is `src/game.h`** (plus `core.h`, `hw.h`, `perks.h`).
   Implement exactly the functions and variables declared there, with those
   names and types. Don't add globals others depend on without adding them to
   `game.h`. File-local helpers are `static`.
2. **Port faithfully.** Follow the legacy routine's logic, order of
   operations, constants and edge cases. Where legacy uses BCD, C uses plain
   binary, and digits are produced only when printing (`put_num`). The score
   is kept in **units of 10 points** (`score`), exactly like legacy.
3. **Write it to be read.** Short functions, named constants, a comment where
   the legacy code encodes a game rule. No assembly in C files.
4. **Write it to be fast** (experiments/c-trial/README.md, "What makes
   Calypsi C fast"):
   - use `small_t` (core.h: a 16-bit type for 0..255 values) or `uint16_t`
     for locals, arithmetic and loop counters, and `uint8_t` only for storage
     arrays. Not `uint_fast8_t`: Calypsi makes it 8 bits wide, and every 8-bit
     access costs a `sep`/`rep` pair;
   - don't index arrays of odd-sized structs in per-frame loops (the enemies
     are struct-of-arrays on purpose);
   - multiply with `hw_mul8()` / `mul16x8()` / `mul16x16()` from `hw.h`, each
     `hw_mul8` in its own statement; divide with `hw_div8()`;
   - avoid 32-bit shifts in per-frame code;
   - no function pointers in per-frame paths (a dense `switch` is fine).
5. **State changes** go through `goto_state()` / `set_pmode()` only. A handler
   that changes state must `return` right after. Entry actions are the
   `enter_*` functions (and `load_stage` for READY); `goto_state` calls them.
6. **Hardware** is touched only through `core.h` functions, the shadow buffers
   (`bg3map`, `oam_buf`, …) and `hw.h` registers. VRAM and CGRAM are uploaded
   by the core. Forced-blank loaders (title, draft, stage) follow the legacy
   sequence: `INIDISP = 0x80; NMITIMEN = 0;` … uploads … then
   `bright = 0x0F; INIDISP = 0x0F; (void)RDNMI; NMITIMEN = 0x81;`.
7. **Compile check** your file on its own:
   `cc65816 --code-model=small --data-model=small -O2 --speed --no-cross-call --strong-inline -I src -o /tmp/x.o src/FILE.c`.
   Don't change other people's files. If the contract is missing something,
   say so in your report rather than editing `game.h`.

## Legacy name → C name

| legacy (main.s) | C |
| --- | --- |
| `PERKS+P_X` (stack counts) | `run_perks.stacks[PERK_X]` |
| `P_TOTAL` | `run_perks.total` |
| `OFFERS`, `CURSOR`, `REROLLS` | `offers[]`, `cursor`, `rerolls` |
| `CHAIN`, `CHAIN_T`, `KILLS`, `AEGIS_C` | `chain`, `chain_t`, `kills`, `aegis_left` |
| `GOAL` | `goal` |
| `JACKMULT`, `MULT` | `stage_mult`, `last_mult` |
| `SHAKE_T`, `SH_X`, `SH_Y` | `shake_t`, `sh_x`, `sh_y` |
| `FL_R/G/B`, `SCR_H/V` | `fl_r/g/b`, `scr_h/v` (core.h) |
| `E_X E_Y E_VX E_VY E_SPD` (word arrays, index = slot*2) | `e_x[] e_y[] e_vx[] e_vy[] e_spd[]` (index = slot) |
| `E_TYPE E_HALF E_TIMER` | `e_type[] e_half[] e_timer[]` (bytes) |
| `I_X I_Y I_ON`, `N_ITEMS` | `i_x[] i_y[] i_on[]`, `n_items` (count, not count*2) |
| `X_X X_Y X_T` | `x_x[] x_y[] x_t[]` |
| `GRID` | `grid` (core.h; cell index = y*64 + x) |
| `BG3MAP` (byte offset row*64+col*2) | `bg3map[MAP(row, col)]` (word = attr<<8 \| tile) |
| `OAM_BUF`, `OAM_HI` | `oam_buf`, `oam_hi` |
| `newly` | the return value of `field_fill()` |
| `print` + `str_ptr`/`text_attr` | `print(at, s, attr)`; it returns the index after the text |
| BCD `score`, `hiscore` | `uint32_t`, still in units of 10 points |
| `SFX ch, data` | `sfx(ch, data)` |
| `jsr goto_state` with `lda #ST_X` | `goto_state(ST_X)` |

Text: a BG3 tile is `character - 32` (the font covers ASCII 32–95), so an entry
is `(attr << 8) | (ch - 32)`. Digits are tile `16 + d`. The 8x8 perk icons are
tiles `120 + perk id`. Set `bg3_dirty = 1` after writing `bg3map`, and
`bg1_dirty = 1` after writing `bg1map`.

## Who ports what

| C file | legacy routines |
| --- | --- |
| `hud.c` | `print put_digit put_bcd put_dec2 put_bcd32_nz clear_row clear_bg3 draw_hud draw_chain_bar draw_owned show_msg`, plus the message and chain-timer parts of `timers_update` (as `hud_update`) |
| `screens.c` | `enter_title st_title enter_draft st_draft draw_cards card_text all_card_text st_ready enter_play st_play enter_pause st_pause enter_dying st_dying enter_clear st_clear enter_gameover st_over`, plus the invuln/shield/freeze part of `timers_update` |
| `player.c` | `player_update try_move retract_step calc_ppos player_hit wipe_trail snap_player`, and the claim half of `do_fill` (after the flood fill, see below) |
| `enemies.c` | `randomize_vel enemies_update enemy_move enemy_collide enemy_cell item_cell check_enclosed collect_item spawn_boom booms_update chrono_scale`, and the enemy/capsule part of `init_entities` (as `enemies_init`) |
| `sprites.c` | `init_oam put_sprite set_small_xy add_shake_x build_oam draft_oam` |
| `stage.c` | `new_run load_stage init_entities` (player and perk setup; it calls `enemies_init`) |
| `sound.c` | `sfx_start ch_base sfx_update music_start music_stop` and all the sfx/jingle/music data |
| `juice.c` | `juice_update`, plus `flash()` |
| `rng.c` | `rand16 rand8` |
| done | `main.c fsm.c perks.c score.c` and `core.s` (boot, NMI, DMA, field kernels, box_scan, SPC700) |

### Closing a cut (`do_fill` → player.c)

The core's `field_fill(seed)` does the flood fill, the claim pass and the edge
pass, and returns the number of newly claimed cells. Everything after it in
legacy `do_fill` is C, in this order:

1. `claimed += newly`
2. `pct = claimed * 3 / 80`, capped at 99
3. `field_redraw_all()`
4. `check_enclosed()`
5. `score_claim(newly)`
6. `snap_player()`
7. `draw_hud()`
8. if `pct >= goal`, `goto_state(ST_CLEAR)` and return; otherwise `sfx(CH_TONE, sfx_claim)`

The seed is the boss's cell, `enemy_cell(0)`. Then, as in legacy `try_move`:
`trail_len = 0`, then `set_pmode(PM_EDGE)`.

## Performance: where the C port stands

`make profile` runs the same scripted play on the C ROM (PROFILE build) and on
the legacy ROM (PERF build), and reports scanlines per stage of the frame (one
frame = 262 lines; the NTSC budget for the main loop is about 225).

| per frame, scanlines (mean) | C | legacy asm |
| --- | ---: | ---: |
| main loop, total | 47 | 49 |
| run_state (st_play) | 28.5 | 26.9 |
| enemies_update | 21 | 23 |
| build_oam | 12 | 18 |
| sfx_update | 3.7 | 2.3 |

A closing cut stalls the game for 12 frames in both (the flood fill is the
same assembly). Rare one-off frames (respawn, HUD redraws) cost more in C,
but none come close to a frame (worst seen: about 160 lines against 95).

What it took, in order of effect:

1. **Compiler flags.** `--no-cross-call` (Calypsi's default turns repeated
   code into shared subroutines: smaller, slower) and `--strong-inline`.
2. **16-bit locals.** `uint_fast8_t` is 8 bits wide in Calypsi; `small_t`
   is not. See rule 4 above.
3. **Don't do work the result can't use.** On the edge there is no trail and
   the player is safe, so `enemies_update` skips the box scans altogether.
4. **Faster kernels where the legacy ones were slow.** `box_scan` (core.s)
   keeps its inner loop 8-bit and counting down: 30 cycles a cell instead of 45.
   `tools/test_selftest.py` checks it against a C model that also matches the
   legacy routine.
5. **Small asm primitives for tight loops Calypsi compiles badly:** `print`,
   `bg3_clear` (core.s) and `field_clear_trail`. Calypsi keeps loop variables on
   the stack; a 32-cell `clear_row` cost 45 cycles a cell in C, 15 in asm.
6. **Tables and macros over calls:** two digits per hardware divide
   (`pairs100`, the `dec2` table), the DSP write and sprite slot macros.

`tools/check_modes.py` gates every build: it rejects the accumulator-width
miscompiles that Calypsi 5.18 produces (experiments/c-trial/README.md).

### A third Calypsi 5.18 miscompile

`a[i][j].ptr[k]`, where `ptr` is a *pointer member* of a struct inside an
array, is compiled as if `k` indexed the struct itself: Calypsi computes
`&a[i][j]`, adds `k`, and dereferences the result as the pointer. Element 0
happens to work. The music sequencer hit this (each bar of a track pointed
at its pattern), and the lead played the first note of a later bar every 4
steps. `src/music.c` now stores a pattern *number* and indexes a 2D array
instead. Arrays *inside* structs (`l->stacks[p]`, `pc->text[l]`) are fine.
`tools/check_modes.py` does not catch this one. The music is checked
note by note against the score by rendering each track on its own (set
`music_mute`).
