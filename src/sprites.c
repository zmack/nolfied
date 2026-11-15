/* Sprite table (OAM) for each state. Slots: 0 player, 1 boss, 2..8 shards,
 * 9..12 capsules, 13..16 explosions; in the draft, 0..2 are the card icons. */
#include "game.h"

#define HIDDEN_Y     224
#define BUSY_SLOTS   20          /* slots rebuilt every frame (high table 0..4) */

#define SLOT_PLAYER  0
#define SLOT_BOSS    1
#define SLOT_SHARD   2           /* + shard slot - 1 */
#define SLOT_ITEM    9
#define SLOT_BOOM    13

#define ATTR_PLAYER  0x30
#define ATTR_SHIELD  0x36
#define ATTR_BOSS    0x32
#define ATTR_SHARD   0x34
#define ATTR_ITEM    0x36
#define ATTR_BOOM    0x34
#define ATTR_ICON    0x39        /* priority 3, palette 4, second name table */

void oam_init(void)
{
    for (uint16_t i = 0; i < 512; i += 4) {
        oam_buf[i] = 0;
        oam_buf[i + 1] = HIDDEN_Y;
        oam_buf[i + 2] = 0;
        oam_buf[i + 3] = 0;
    }
    for (uint_fast8_t i = 0; i < 32; i++)
        oam_hi[i] = 0;
}

/* x is 9 bits (bit 8 goes to the high table); big selects the large size */
static void put_sprite(uint_fast8_t slot, uint16_t x, uint_fast8_t y, uint_fast8_t tile,
                       uint_fast8_t attr, uint_fast8_t big)
{
    uint16_t o = (uint16_t)slot << 2;
    oam_buf[o] = (uint8_t)x;
    oam_buf[o + 1] = y;
    oam_buf[o + 2] = tile;
    oam_buf[o + 3] = attr;

    /* 2 bits per sprite in the high table: X bit 8, size. 16-bit arithmetic
     * on purpose: Calypsi 5.18 shifted an 8-bit `bits <<= 2` with a 16-bit
     * instruction and corrupted the loop counter next to it (the build runs
     * tools/check_modes.py to catch that class of miscompile). */
    static const uint8_t place[4] = { 1, 4, 16, 64 };   /* << 0, 2, 4, 6 */
    uint_fast8_t bits = ((x >> 8) & 1) | (big ? 2 : 0);
    oam_hi[slot >> 2] |= (uint8_t)(bits * place[slot & 3]);
}

/* x: the screen shake is added, sign-extended */
static uint16_t add_shake_x(uint16_t x)
{
    return x + (int16_t)sh_x;
}

/* small sprite centred on field pixel (px, py) */
static void set_small_xy(uint_fast8_t slot, uint_fast8_t px, uint_fast8_t py,
                         uint_fast8_t tile, uint_fast8_t attr)
{
    put_sprite(slot, add_shake_x(px), (uint8_t)(py + 15 + sh_y), tile, attr, 0);
}

/* the three card icons of the draft screen
 *
 * Locals and parameters in this file are uint_fast8_t (16-bit) on purpose:
 * with 8-bit locals Calypsi 5.18 emitted blocks reachable in both
 * accumulator widths here (tools/check_modes.py), which crashed the game. */
static void draft_oam(void)
{
    static const uint8_t icon_x[3] = { 1 * 8 + 20, 11 * 8 + 20, 21 * 8 + 20 };
    for (uint_fast8_t i = 0; i < 3; i++) {
        uint_fast8_t p = offers[i];
        uint_fast8_t tile = (uint8_t)(((p >> 2) << 6) | ((p & 3) << 2));
        uint_fast8_t bob = (i == cursor && (nmi_count & 0x10)) ? 2 : 0;  /* selected icon bobs */
        put_sprite(i, icon_x[i], 47 - bob, tile, ATTR_ICON, 1);
    }
}

void build_oam(uint8_t view_state)
{
    for (uint16_t o = 0; o < BUSY_SLOTS * 4; o += 4) {
        oam_buf[o] = 0;
        oam_buf[o + 1] = HIDDEN_Y;
    }
    for (uint_fast8_t i = 0; i < 5; i++)
        oam_hi[i] = 0;

    if (view_state == ST_DRAFT) {
        draft_oam();
        return;
    }
    if (state != ST_READY && state != ST_PLAY && state != ST_PAUSE && state != ST_DYING)
        return;

    uint_fast8_t frame = nmi_count;

    /* player: hidden while dying, blinks while invulnerable */
    if (view_state != ST_DYING && !(invuln && (frame & 0x02))) {
        uint_fast8_t glow = (shield && (frame & 0x04)) ? ATTR_SHIELD : ATTR_PLAYER;
        set_small_xy(SLOT_PLAYER, ppx, ppy, (frame & 0x08) >> 2, glow);
    }

    /* boss: 16x16, drawn from its top-left */
    if (e_type[0]) {
        put_sprite(SLOT_BOSS, add_shake_x((e_x[0] >> 8) - 8),
                   (uint8_t)((e_y[0] >> 8) + 7 + sh_y),
                   32 + ((frame & 0x10) >> 2), ATTR_BOSS, 1);
    }

    /* shards */
    uint_fast8_t shard_tile = 4 + ((frame & 0x04) >> 1);
    for (uint_fast8_t s = 1; s < MAX_ENEMIES; s++) {
        if (e_type[s] == E_SHARD)
            set_small_xy(SLOT_SHARD + s - 1, e_x[s] >> 8, e_y[s] >> 8,
                         shard_tile, ATTR_SHARD);
    }

    /* capsules */
    for (uint_fast8_t i = 0; i < MAX_ITEMS; i++) {
        if (i_on[i])
            set_small_xy(SLOT_ITEM + i, i_x[i], i_y[i], 8, ATTR_ITEM);
    }

    /* explosions: flicker between two frames */
    for (uint_fast8_t b = 0; b < MAX_BOOMS; b++) {
        if (x_t[b])
            set_small_xy(SLOT_BOOM + b, x_x[b], x_y[b],
                         (x_t[b] & 0x04) ? 10 : 12, ATTR_BOOM);
    }
}
