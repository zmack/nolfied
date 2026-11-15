/* Sprite table (OAM) for each state.
 *
 * Slots: 0 player, 1 boss, 2..8 shards, 9..12 capsules, 13..16 explosions,
 * 17..19 unused; on the draft screen 0..2 are the three card icons.
 *
 * Each sprite is four stores; the high table is a constant (see HI_PLAY).
 *
 * Locals are uint_fast8_t (16-bit): with 8-bit locals Calypsi 5.18 produced
 * code reachable in both accumulator widths here (tools/check_modes.py).
 */
#include "game.h"

#define HIDDEN_Y     224
#define BUSY_SLOTS   20          /* slots rebuilt every frame: oam_hi[0..4] */

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

/* The high table: 2 bits per slot (X bit 8, large size). No sprite's X ever
 * leaves 0..255 (the boss's leftmost position is 5, shake included; small
 * sprites stay within the 240-pixel field), so only the size bits matter, and
 * they are fixed: the boss in play, the three card icons in the draft. */
#define HI_PLAY   0x08          /* slot 1 large */
#define HI_DRAFT  0x2A          /* slots 0, 1, 2 large */

/* Write the slot at byte offset `at` (slot * 4). A macro: Calypsi does not
 * reliably inline, and this runs ~17 times a frame. */
#define SLOT(at, x, y, tile, attr) do {         \
        oam_buf[(at)]     = (uint8_t)(x);       \
        oam_buf[(at) + 1] = (uint8_t)(y);       \
        oam_buf[(at) + 2] = (uint8_t)(tile);    \
        oam_buf[(at) + 3] = (uint8_t)(attr);    \
    } while (0)

#define HIDE(at) (oam_buf[(at) + 1] = HIDDEN_Y)   /* off screen: Y is enough */

/* a 16x16 sprite centred on field pixel (px, py), with the screen shake */
#define SMALL(at, px, py, tile, attr) \
    SLOT(at, (px) + shake_x, (py) + 15 + shake_y, tile, attr)

void build_oam(uint8_t view_state)
{
    uint16_t at;

    if (view_state == ST_DRAFT) {
        /* the three card icons; the selected one bobs */
        static const uint8_t icon_x[3] = { 1 * 8 + 20, 11 * 8 + 20, 21 * 8 + 20 };
        at = 0;
        for (uint_fast8_t i = 0; i < 3; i++, at += 4) {
            uint_fast8_t p = offers[i];
            uint_fast8_t tile = ((p >> 2) << 6) | ((p & 3) << 2);
            uint_fast8_t bob = (i == cursor && (nmi_count & 0x10)) ? 2 : 0;
            SLOT(at, icon_x[i], 47 - bob, tile, ATTR_ICON);
        }
        oam_hi[0] = HI_DRAFT;
        for (; at < BUSY_SLOTS * 4; at += 4)
            HIDE(at);
        return;
    }

    oam_hi[0] = HI_PLAY;
    if (state != ST_READY && state != ST_PLAY && state != ST_PAUSE && state != ST_DYING) {
        for (at = 0; at < BUSY_SLOTS * 4; at += 4)
            HIDE(at);
        return;
    }

    uint_fast8_t frame = nmi_count;
    uint_fast8_t shake_x = (uint8_t)sh_x;     /* wraps like the hardware does */
    uint_fast8_t shake_y = (uint8_t)sh_y;

    /* slot 0: player, hidden while dying, blinking while invulnerable */
    if (view_state != ST_DYING && !(invuln && (frame & 0x02))) {
        uint_fast8_t glow = (shield && (frame & 0x04)) ? ATTR_SHIELD : ATTR_PLAYER;
        SMALL(0, ppx, ppy, (frame & 0x08) >> 2, glow);
    } else {
        HIDE(0);
    }

    /* slot 1: the boss, a 32x32 sprite drawn from its top-left */
    if (e_type[0])
        SLOT(4, (e_x[0] >> 8) - 8 + shake_x, (e_y[0] >> 8) + 7 + shake_y,
             32 + ((frame & 0x10) >> 2), ATTR_BOSS);
    else
        HIDE(4);

    /* slots 2..8: shards */
    uint_fast8_t shard_tile = 4 + ((frame & 0x04) >> 1);
    at = 8;
    for (uint_fast8_t s = 1; s < MAX_ENEMIES; s++, at += 4) {
        if (e_type[s] == E_SHARD)
            SMALL(at, e_x[s] >> 8, e_y[s] >> 8, shard_tile, ATTR_SHARD);
        else
            HIDE(at);
    }

    /* slots 9..12: capsules */
    for (uint_fast8_t i = 0; i < MAX_ITEMS; i++, at += 4) {
        if (i_on[i])
            SMALL(at, i_x[i], i_y[i], 8, ATTR_ITEM);
        else
            HIDE(at);
    }

    /* slots 13..16: explosions, flickering between two frames */
    for (uint_fast8_t b = 0; b < MAX_BOOMS; b++, at += 4) {
        if (x_t[b])
            SMALL(at, x_x[b], x_y[b], (x_t[b] & 0x04) ? 10 : 12, ATTR_BOOM);
        else
            HIDE(at);
    }
}
