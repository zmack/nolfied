/* Player: movement along the edge, cutting, retracting, hits, closing a cut.
 * (legacy player_update, try_move, retract_step, calc_ppos, player_hit,
 * wipe_trail, snap_player and the claim half of do_fill) */
#include "game.h"
#include "hw.h"

uint16_t p_idx, start_idx, trail_len;
uint8_t  pspeed, pmove_timer;
uint8_t  ppx, ppy;

#define AEGIS_INVULN 90          /* frames of invulnerability after an AEGIS block */
#define SNAP_MAX_R   24

/* cell index offsets: up, down, left, right (two's complement in 16 bits) */
#define D_UP    ((uint16_t)-64)
#define D_DOWN  64u
#define D_LEFT  ((uint16_t)-1)
#define D_RIGHT 1u

/* player centre in field pixels (cells are 4x4 pixels) */
void calc_ppos(void)
{
    ppx = (uint8_t)(((p_idx & 0x3F) << 2) | 2);
    ppy = (uint8_t)(((p_idx >> 4) & 0xFC) | 2);
}

/* clear the current trail and put the player back where the cut started */
void wipe_trail(void)
{
    for (uint16_t i = 0; i < trail_len; i++) {
        uint16_t cell = trail[i];
        grid[cell] = C_OPEN;
        field_update_cell(cell);
    }
    trail_len = 0;
    if (pmode != PM_EDGE)
        p_idx = start_idx;
    set_pmode(PM_EDGE);
    calc_ppos();
}

/* after a fill: make sure the player stands on an edge cell */
void snap_player(void)
{
    if (grid[p_idx] == C_EDGE)
        return;
    int16_t cx = p_idx & 0x3F;
    int16_t cy = p_idx >> 6;
    for (int16_t r = 1; r < SNAP_MAX_R; r++) {
        for (int16_t dy = -r; dy <= r; dy++) {
            int16_t y = cy + dy;
            if (y < 0 || y >= FIELD_H)
                continue;
            uint16_t row = (uint16_t)y << 6;
            for (int16_t dx = -r; dx <= r; dx++) {
                int16_t x = cx + dx;
                if (x < 0 || x >= FIELD_W)
                    continue;
                if (grid[row + x] == C_EDGE) {
                    p_idx = row + x;
                    return;
                }
            }
        }
    }
}

/* Claim everything the boss cannot reach, then score and check the goal
 * (legacy do_fill after the flood fill; docs/PORTING.md "Closing a cut"). */
static void close_cut(void)
{
    PROF(8);
    uint16_t newly = field_fill(enemy_cell(0));
    PROF(9);
    claimed += newly;
    uint16_t q = hw_div8(claimed + claimed + claimed, 80);   /* claimed * 3 / 80 */
    pct = q >= 100 ? 99 : (uint8_t)q;
    field_redraw_all();
    PROF(10);
    check_enclosed();
    PROF(11);
    score_claim(newly);
    PROF(12);
    snap_player();
    PROF(13);
    draw_hud();
    PROF(14);
    if (pct >= goal) {
        goto_state(ST_CLEAR);
        return;
    }
    sfx(CH_TONE, sfx_claim);
}

static void add_trail(uint16_t cell)
{
    grid[cell] = C_TRAIL;
    p_idx = cell;
    trail[trail_len] = cell;
    trail_len++;
    field_update_cell(cell);
}

/* Step one cell in a direction. Returns 1 if the player moved. */
static uint_fast8_t try_move(uint16_t delta, uint_fast8_t cut)
{
    uint16_t cell = p_idx + delta;
    uint8_t g = grid[cell];

    if (pmode == PM_EDGE) {
        if (g == C_EDGE) {                  /* walk along the edge */
            p_idx = cell;
            return 1;
        }
        if (g != C_OPEN || !cut)
            return 0;
        start_idx = p_idx;                  /* start a cut */
        trail_len = 0;
        set_pmode(PM_DRAW);
        sfx(CH_TONE, sfx_cut);
        add_trail(cell);
        return 1;
    }
    if (g == C_OPEN) {
        add_trail(cell);
        return 1;
    }
    if (g != C_EDGE)
        return 0;
    p_idx = cell;                           /* the cut reaches an edge */
    calc_ppos();
    close_cut();                            /* may enter ST_CLEAR */
    trail_len = 0;                          /* the trail is now claimed area: */
    set_pmode(PM_EDGE);                     /* mode and trail change together */
    return 1;
}

/* take back one trail cell; the trail empty means back on the edge */
static void retract_step(void)
{
    if (trail_len == 0) {
        p_idx = start_idx;
        set_pmode(PM_EDGE);
        return;
    }
    trail_len--;
    uint16_t cell = trail[trail_len];
    p_idx = trail_len ? trail[trail_len - 1] : start_idx;
    grid[cell] = C_OPEN;
    field_update_cell(cell);
    if (trail_len == 0)
        set_pmode(PM_EDGE);
}

void player_update(void)
{
    uint_fast8_t cut = (joy & BTN_CUT) != 0;

    if (pmode == PM_RETRACT) {
        if (!cut) {
            retract_step();                 /* retract at 2 cells per frame */
            if (pmode == PM_RETRACT)
                retract_step();
            return;
        }
        set_pmode(PM_DRAW);
    } else if (pmode == PM_DRAW && !cut) {
        set_pmode(PM_RETRACT);
        return;
    }

    if (--pmove_timer != 0)
        return;
    pmove_timer = pspeed;
    uint16_t j = joy;
    if ((j & BTN_UP) && try_move(D_UP, cut))
        return;
    if ((j & BTN_DOWN) && try_move(D_DOWN, cut))
        return;
    if ((j & BTN_LEFT) && try_move(D_LEFT, cut))
        return;
    if ((j & BTN_RIGHT) && try_move(D_RIGHT, cut))
        return;
    pmove_timer = 1;                        /* nothing moved: try again next frame */
}

void player_hit(void)
{
    if (state != ST_PLAY || invuln || shield)
        return;
    if (aegis_left) {                       /* AEGIS soaks the hit */
        aegis_left--;
        wipe_trail();
        invuln = AEGIS_INVULN;
        flash(0, 10, 16);
        shake_t = 12;
        show_msg("AEGIS BLOCKED THE HIT!");
        sfx(CH_NOISE, sfx_kill);
        return;
    }
    goto_state(ST_DYING);
}
