/* NOLFIED game: shared state and the functions each module provides.
 *
 * Module map (each line: file, what it owns)
 *   main.c     main loop, joypad, frame handshake
 *   fsm.c      game-state and player-mode state machines (spec/GameFSM.tla)
 *   stage.c    new run, stage setup (field, entities, picture)
 *   player.c   player movement, cutting, retracting, hits, closing a cut
 *   enemies.c  boss and shards, capsules (items), explosions
 *   perks.c    the perk deck (perk_defs.h), the loadout, draft offers
 *   score.c    chips x mult scoring of a claim
 *   hud.c      text, numbers, HUD, messages (BG3)
 *   screens.c  title, draft, ready, clear, game over and pause screens
 *   sprites.c  sprite table (OAM) for each state
 *   sound.c    sound effects, jingles, music
 *   juice.c    screen shake and flashes
 *   rng.c      random numbers
 *   core.s     assembly core: see core.h
 *
 * Variables the test tools look up by name (build/nolfied.lbl) are plain
 * globals with the names below; don't rename them without updating tools/.
 */
#ifndef GAME_H
#define GAME_H

#include <stdint.h>
#include "core.h"

/* ---- game states (spec/GameFSM.tla) -------------------------------------- */
enum {
    ST_TITLE, ST_READY, ST_PLAY, ST_DYING, ST_CLEAR, ST_OVER, ST_DRAFT, ST_PAUSE,
    ST_BOOT,                /* only ever the initial value */
    ST_COUNT = ST_BOOT
};
enum { PM_EDGE, PM_DRAW, PM_RETRACT };        /* player modes */

/* ---- text attributes (BG3 tile high byte: priority + palette) ------------ */
#define ATTR_W 0x20    /* white  */
#define ATTR_Y 0x24    /* yellow */
#define ATTR_L 0x28    /* logo   */
#define ATTR_G 0x2C    /* green  */
#define ATTR_P 0x30    /* pink   */
#define ATTR_O 0x34    /* orange */

/* ---- main.c ---------------------------------------------------------------- */
extern uint16_t joy, joy_prev, joy_new;       /* held, previous, newly pressed */
extern uint16_t loops;                        /* main-loop iterations (tests)  */

/* ---- fsm.c ----------------------------------------------------------------- */
extern uint8_t state;
extern uint8_t pmode;
extern uint8_t fsm_errs, fsm_kind, fsm_from, fsm_to;   /* illegal transitions */
void goto_state(uint8_t to);       /* runs the target's entry action, then commits */
void set_pmode(uint8_t to);
void fsm_check(void);              /* once per frame: pmode == EDGE <=> trail_len == 0 */
void run_state(void);              /* calls the current state's per-frame handler */

/* ---- shared game state -------------------------------------------------------- */
extern uint16_t timer;             /* frames left in a timed state */
extern uint8_t  lives, stage, pct;
extern uint16_t goal;              /* percent needed to clear the stage */
extern uint16_t claimed;           /* interior cells claimed this stage */
extern uint32_t score, hiscore;    /* in units of 10 points */
extern uint16_t invuln, shield, freeze, msg_timer;

/* ---- stage.c --------------------------------------------------------------- */
void new_run(void);                /* fresh perks, chain, lives, stage 1 */
void load_stage(void);             /* entry action of ST_READY */
void init_entities(void);          /* player, enemies, capsules for the stage */

/* ---- player.c -------------------------------------------------------------- */
extern uint16_t p_idx, start_idx, trail_len;  /* cell indices; trail length */
extern uint8_t  pspeed, pmove_timer;           /* frames per cell / countdown */
extern uint8_t  ppx, ppy;                      /* player centre, field pixels */
void player_update(void);
void calc_ppos(void);
void wipe_trail(void);             /* remove the trail, back to its start, EDGE */
void player_hit(void);             /* an enemy touched the trail or the player */
void snap_player(void);            /* after a fill: move onto the nearest edge */

/* ---- enemies.c --------------------------------------------------------------- */
#define MAX_ENEMIES 8              /* slot 0 = boss, 1..7 = shards */
#define MAX_ITEMS   4
#define MAX_BOOMS   4
enum { E_NONE, E_BOSS, E_SHARD };
extern uint16_t e_x[MAX_ENEMIES], e_y[MAX_ENEMIES];     /* 8.8 fixed, field px */
extern int16_t  e_vx[MAX_ENEMIES], e_vy[MAX_ENEMIES];
extern uint16_t e_spd[MAX_ENEMIES];
extern uint8_t  e_type[MAX_ENEMIES], e_half[MAX_ENEMIES], e_timer[MAX_ENEMIES];
extern uint8_t  i_x[MAX_ITEMS], i_y[MAX_ITEMS], i_on[MAX_ITEMS];   /* capsules */
extern uint8_t  x_x[MAX_BOOMS], x_y[MAX_BOOMS], x_t[MAX_BOOMS];    /* explosions */
extern uint8_t  n_items;
void     enemies_init(void);       /* boss, shards, capsules for the current stage */
void     enemies_update(void);     /* move (unless frozen) and collide */
void     booms_update(void);
void     spawn_boom(uint8_t x, uint8_t y);
uint16_t enemy_cell(uint8_t slot);
void     check_enclosed(void);     /* after a fill: kill shards, collect capsules */

/* ---- perks.c / score.c (perks.h has the types) ------------------------------- */
#include "perks.h"
extern loadout run_perks;          /* what the player owns */
extern uint8_t offers[3];          /* perks on offer in the draft */
extern uint16_t cursor;            /* selected offer */
extern uint8_t  rerolls;
extern uint8_t  chain;             /* chain links */
extern uint16_t chain_t;           /* frames until the chain breaks */
extern uint8_t  kills;             /* shards destroyed this stage */
extern uint8_t  aegis_left;        /* AEGIS charges this stage */
extern uint16_t stage_mult;        /* +mult banked this stage (JACKPOT) */
extern uint16_t last_mult;         /* multiplier of the last claim */
void gen_offers(void);
void take_offer(void);             /* apply offers[cursor] to run_perks */
void score_claim(uint16_t chips);  /* score a claim, popup, chain, juice, stasis */

/* ---- hud.c ---------------------------------------------------------------------- */
#define MAP(row, col) ((row) * 32 + (col))     /* BG3 map index */
uint16_t print(uint16_t at, const char *s, uint8_t attr);   /* returns next index */
uint16_t put_digit(uint16_t at, uint8_t d, uint8_t attr);
uint16_t put_dec2(uint16_t at, uint8_t v, uint8_t attr);     /* 2 digits, 0-padded */
uint16_t put_num(uint16_t at, uint32_t v, uint8_t attr);     /* no leading zeros */
uint16_t put_score(uint16_t at, uint32_t units, uint8_t attr); /* 8 digits: units*10 */
void clear_row(uint8_t row);
void clear_bg3(void);
void draw_hud(void);
void draw_chain_bar(void);
void draw_owned(uint8_t row);      /* owned perks as mini icons + stack counts */
void show_msg(const char *s);      /* bottom row, for a few seconds */
void hud_update(void);             /* per-frame: message timeout, chain timer */

/* ---- screens.c --------------------------------------------------------------- */
void enter_title(void);  void st_title(void);
void enter_draft(void);  void st_draft(void);
                         void st_ready(void);
void enter_play(void);   void st_play(void);
void enter_pause(void);  void st_pause(void);
void enter_dying(void);  void st_dying(void);
void enter_clear(void);  void st_clear(void);
void enter_gameover(void); void st_over(void);

/* ---- sprites.c ----------------------------------------------------------------- */
void oam_init(void);
void build_oam(uint8_t view_state);

/* ---- sound.c --------------------------------------------------------------------- */
typedef struct { uint8_t dur; uint16_t pitch; uint8_t vol; } note;   /* dur 0: end, 0xFF: loop */
enum { CH_TONE, CH_NOISE, CH_JINGLE, CH_MUSIC, CH_COUNT };
extern const note sfx_cut[], sfx_claim[], sfx_item[], sfx_death[], sfx_kill[], sfx_tick[];
extern const note jingle_start[], jingle_clear[], jingle_over[], jingle_draft[];
void sfx(uint8_t channel, const note *n);
void sfx_update(void);             /* once per frame */
void music_start(void);
void music_stop(void);

/* ---- juice.c ------------------------------------------------------------------- */
extern uint8_t shake_t;            /* frames of screen shake left */
extern int8_t  sh_x, sh_y;         /* current shake offset */
void juice_update(void);
void flash(uint8_t r, uint8_t g, uint8_t b);

/* ---- rng.c ------------------------------------------------------------------- */
extern uint16_t rng;
uint16_t rand16(void);

#endif
