/* Enemies (boss + shards), capsules (items) and explosions. */
#include "game.h"
#include "hw.h"

uint16_t e_x[MAX_ENEMIES], e_y[MAX_ENEMIES];
int16_t  e_vx[MAX_ENEMIES], e_vy[MAX_ENEMIES];
uint16_t e_spd[MAX_ENEMIES];
uint16_t e_half[MAX_ENEMIES];
uint8_t  e_type[MAX_ENEMIES], e_timer[MAX_ENEMIES];
uint8_t  i_x[MAX_ITEMS], i_y[MAX_ITEMS], i_on[MAX_ITEMS];
uint8_t  x_x[MAX_BOOMS], x_y[MAX_BOOMS], x_t[MAX_BOOMS];
uint8_t  n_items;

#define BOSS_HALF       11
#define SHARD_HALF      4
#define BOSS_RETARGET   60       /* frames until the boss first changes course */
#define BOOM_FRAMES     24
#define MAX_SHARDS      7

#define SCORE_ITEM      100      /* units of 10 points */
#define SCORE_KILL      50

/* high byte of an 8.8 position = field pixel */
#define PX(v) ((uint8_t)((v) >> 8))

/* ---- cells -------------------------------------------------------------------- */

uint16_t enemy_cell(uint8_t slot)
{
    return ((uint16_t)(PX(e_y[slot]) & 0xFC) << 4) + (PX(e_x[slot]) >> 2);
}

static uint16_t item_cell(uint8_t slot)
{
    return ((uint16_t)(i_y[slot] & 0xFC) << 4) + (i_x[slot] >> 2);
}

/* ---- setup ---------------------------------------------------------------------- */

/* random direction with speed e_spd: each axis gets spd - (0..63), random sign */
static void randomize_vel(uint8_t s)
{
    uint16_t r = rand16();
    int16_t vx = (int16_t)(e_spd[s] - (r & 0x3F));
    int16_t vy = (int16_t)(e_spd[s] - ((r >> 6) & 0x3F));
    if (r & 0x8000)
        vx = -vx;
    if (r & 0x4000)
        vy = -vy;
    e_vx[s] = vx;
    e_vy[s] = vy;
}

/* CHRONO slows enemies by 20% of their base speed per stack */
static uint16_t chrono_scale(uint16_t v)
{
    uint16_t step = hw_div8(v, 5);
    for (uint8_t n = run_perks.stacks[PERK_CHRONO]; n; n--)
        v -= step;
    return v;
}

void enemies_init(void)
{
    for (uint8_t s = 0; s < MAX_ENEMIES; s++) {
        e_x[s] = e_y[s] = 0;
        e_vx[s] = e_vy[s] = 0;
        e_spd[s] = 0;
        e_type[s] = e_timer[s] = 0;
        e_half[s] = 0;
    }
    for (uint8_t i = 0; i < MAX_ITEMS; i++)
        i_x[i] = i_y[i] = i_on[i] = 0;
    for (uint8_t b = 0; b < MAX_BOOMS; b++)
        x_x[b] = x_y[b] = x_t[b] = 0;

    /* boss */
    e_type[0] = E_BOSS;
    e_x[0] = 120u << 8;
    e_y[0] = 80u << 8;
    e_half[0] = BOSS_HALF;
    uint16_t spd = ((uint16_t)stage << 4) + ((uint16_t)stage << 3) + 0xA8;   /* stage*24 */
    if (spd >= 0x200)
        spd = 0x200;
    e_spd[0] = chrono_scale(spd);
    e_timer[0] = BOSS_RETARGET;
    randomize_vel(0);

    /* shards: stage + 1, at most 7 */
    uint8_t n = stage + 1;
    if (n >= 8)
        n = MAX_SHARDS;
    uint16_t sspd = ((uint16_t)stage << 4) + ((uint16_t)stage << 2) + 0xF0;  /* stage*20 */
    if (sspd >= 0x240)
        sspd = 0x240;
    sspd = chrono_scale(sspd);
    for (uint8_t s = 1; s <= n; s++) {
        e_type[s] = E_SHARD;
        e_half[s] = SHARD_HALF;
        e_x[s] = (uint16_t)(((rand16() & 0x7F) + 56) << 8);
        e_y[s] = (uint16_t)(((rand16() & 0x7F) + 24) << 8);
        e_spd[s] = sspd;
        randomize_vel(s);
    }

    /* capsules: 2 + LUCKY */
    n_items = 2 + run_perks.stacks[PERK_LUCKY];
    for (uint8_t i = 0; i < n_items; i++) {
        i_on[i] = 1;
        i_x[i] = (uint8_t)((((rand16() & 0x1F) + 14) << 2) | 2);
        i_y[i] = (uint8_t)((((rand16() & 0x1F) + 6) << 2) | 2);
    }
}

/* ---- per frame -------------------------------------------------------------------- */

/* move one axis at a time; a claimed or edge cell in the way reverses it */
/* enemy_move() is in the core (core.h): one step, bouncing off claimed area */

/* |a - b| < reach, for pixel coordinates (0..255): one unsigned compare */
#define NEAR(a, b, reach) ((uint16_t)((a) - (b) + (reach) - 1) < (uint16_t)(2 * (reach) - 1))

static void retarget_boss(void)
{
    e_timer[0] = (rand16() & 0x3F) + 50;
    randomize_vel(0);
}

/* Move every enemy (unless frozen), then check whether it touches the trail
 * (anywhere under its box) or the player.
 *
 * Both only matter while the player is off the edge: on the edge there is no
 * trail (fsm_check() asserts pmode == EDGE <=> trail_len == 0) and the player
 * is safe, so the box scans are skipped. One player_hit() per enemy is enough:
 * after a hit the player is invulnerable or dying and a second does nothing. */
void enemies_update(void)
{
    uint16_t moving = freeze == 0;
    uint16_t exposed = pmode != PM_EDGE;
    uint16_t px = ppx, py = ppy;
    for (uint16_t s = 0; s < MAX_ENEMIES; s++) {
        uint16_t type = e_type[s];
        if (type == E_NONE)
            continue;
        if (moving) {
            enemy_move(s);
            if (type == E_BOSS && --e_timer[0] == 0)
                retarget_boss();
        }
        if (!exposed)
            continue;
        uint16_t hit = enemy_box_flags(s) & F_TRAIL;
        if (!hit && pmode != PM_EDGE) {
            uint16_t reach = e_half[s] + 3;
            hit = NEAR(PX(e_x[s]), px, reach) && NEAR(PX(e_y[s]), py, reach);
        }
        if (hit)
            player_hit();
    }
}

/* ---- capsules ----------------------------------------------------------------------- */

static void collect_item(void)
{
    score += SCORE_ITEM;
    sfx(CH_TONE, sfx_item);
    /* JACKPOT: +4 mult per stack for this stage */
    stage_mult += (uint8_t)(run_perks.stacks[PERK_JACKPOT] << 2);
    flash(6, 6, 0);
    switch (rand16() & 3) {
    case 0:
        pspeed = 1;
        show_msg("SPEED UP!");
        break;
    case 1:
        shield = 600;
        show_msg("SHIELD ON!");
        break;
    case 2:
        freeze = 300;
        show_msg("ENEMIES FROZEN!");
        break;
    default:
        if (lives < 9)
            lives++;
        show_msg("EXTRA LIFE!");
        break;
    }
}

/* after a fill: destroy enclosed shards, collect enclosed capsules */
void check_enclosed(void)
{
    for (uint8_t s = 1; s < MAX_ENEMIES; s++) {
        if (e_type[s] != E_SHARD || grid[enemy_cell(s)] == C_OPEN)
            continue;
        e_type[s] = E_NONE;
        kills++;
        spawn_boom(PX(e_x[s]), PX(e_y[s]));
        score += SCORE_KILL;
        sfx(CH_NOISE, sfx_kill);
    }
    for (uint8_t i = 0; i < MAX_ITEMS; i++) {
        if (!i_on[i] || grid[item_cell(i)] == C_OPEN)
            continue;
        i_on[i] = 0;
        collect_item();
    }
}

/* ---- explosions ------------------------------------------------------------------------ */

void spawn_boom(uint8_t x, uint8_t y)
{
    for (uint8_t b = 0; b < MAX_BOOMS; b++) {
        if (x_t[b] == 0) {
            x_t[b] = BOOM_FRAMES;
            x_x[b] = x;
            x_y[b] = y;
            return;
        }
    }
}

void booms_update(void)
{
    for (uint8_t b = 0; b < MAX_BOOMS; b++)
        if (x_t[b])
            x_t[b]--;
}
