/* Text, numbers, the HUD and messages: everything drawn on BG3. */
#include "game.h"
#include "hw.h"

#define ROW_MSG       27
#define MSG_FRAMES    150
#define TILE_HEART    10            /* '*' in the font is drawn as a heart */
#define TILE_BAR      ('=' - 32)
#define CHAIN_BAR_MAX 4
#define CHAIN_BAR_REDRAW 0xFF       /* forces draw_chain_bar to repaint */

static const char s_score[]  = "SCORE";
static const char s_stage[]  = "STAGE";
static const char s_area[]   = "AREA   %/  %";
static const char s_chain[]  = "CHAIN";
static const char s_broken[] = "CHAIN BROKEN!";

static uint8_t chain_bar;           /* cells of the chain-timer bar now shown */

/* ---- text -------------------------------------------------------------- */

static inline uint16_t cell(uint8_t attr, uint8_t tile)
{
    return ((uint16_t)attr << 8) | tile;
}

/* print() is in the core (core.h): it runs ~30 characters per HUD redraw */

uint16_t put_digit(uint16_t at, uint8_t d, uint8_t attr)
{
    bg3map[at] = cell(attr, 16 + (d & 0x0F));
    return at + 1;
}

/* 0..99 as two decimal digits, packed tens:ones (one table read instead of a
 * divide per number) */
static const uint8_t dec2[100] = {
#define ROW(t) 0x##t##0, 0x##t##1, 0x##t##2, 0x##t##3, 0x##t##4, \
               0x##t##5, 0x##t##6, 0x##t##7, 0x##t##8, 0x##t##9
    ROW(0), ROW(1), ROW(2), ROW(3), ROW(4), ROW(5), ROW(6), ROW(7), ROW(8), ROW(9)
#undef ROW
};

/* two digits at p: tiles 16 + tens, 16 + ones */
#define PUT_PAIR(p, base, pair) do {                    \
        small_t d_ = dec2[pair];                        \
        (p)[0] = (base) + (d_ >> 4);                    \
        (p)[1] = (base) + (d_ & 0x0F);                  \
    } while (0)

uint16_t put_dec2(uint16_t at, uint8_t v, uint8_t attr)
{
    if (v > 99)
        v = 99;
    PUT_PAIR(&bg3map[at], ((uint16_t)attr << 8) + 16, v);
    return at + 2;
}

/* v in base 100, least significant pair first: n pairs (enough for v).
 *
 * Long division by 100, one byte at a time, on the 16/8 hardware divider:
 * each partial dividend is (remainder << 8) | byte < 25600, so every step is
 * a single 16-cycle hardware divide, and each round yields two digits.
 * (C's `v / 100` would call Calypsi's software 32-bit division.) */
typedef union { uint32_t u; uint8_t b[4]; } bytes32;    /* b[3] is the top byte */

static void pairs100(uint32_t v, uint8_t *pair, small_t n)
{
    bytes32 x = { v };
    small_t top = 3;                  /* highest byte that is not 0 */
    while (top && x.b[top] == 0)
        top--;
    for (small_t i = 0; i < n; i++) {
        uint16_t rem = 0;
        for (small_t k = top + 1; k--; ) {
            x.b[k] = (uint8_t)hw_div8((rem << 8) | x.b[k], 100);
            rem = RDMPY;
        }
        pair[i] = (uint8_t)rem;
        while (top && x.b[top] == 0)
            top--;
    }
}

uint16_t put_num(uint16_t at, uint32_t v, uint8_t attr)
{
    uint8_t pair[5];
    pairs100(v, pair, 5);
    small_t n = 5;
    while (n > 1 && pair[n - 1] == 0)
        n--;
    uint16_t base = ((uint16_t)attr << 8) + 16;
    uint16_t *p = &bg3map[at];
    small_t top = dec2[pair[--n]];    /* the leading pair: no leading zero */
    if (top >> 4)
        *p++ = base + (top >> 4);
    *p++ = base + (top & 0x0F);
    while (n) {
        PUT_PAIR(p, base, pair[--n]);
        p += 2;
    }
    return (uint16_t)(p - bg3map);
}

/* The score is kept in tens: print 7 digits (the top one of four pairs is
 * dropped: units < 10^7), then the fixed trailing zero. */
uint16_t put_score(uint16_t at, uint32_t units, uint8_t attr)
{
    uint8_t pair[4];
    pairs100(units, pair, 4);
    uint16_t base = ((uint16_t)attr << 8) + 16;
    uint16_t *p = &bg3map[at];
    *p++ = base + (dec2[pair[3]] & 0x0F);
    PUT_PAIR(p, base, pair[2]);
    PUT_PAIR(p + 2, base, pair[1]);
    PUT_PAIR(p + 4, base, pair[0]);
    p[6] = base;                      /* the trailing 0 */
    return at + 8;
}

void clear_row(uint8_t row)
{
    bg3_clear(MAP(row, 0), 32);
}

void clear_bg3(void)
{
    bg3_clear(0, 1024);
}

/* ---- HUD --------------------------------------------------------------- */

void draw_hud(void)
{
    PROF(24);
    print(MAP(1, 1), s_score, ATTR_W);
    print(MAP(1, 19), s_stage, ATTR_W);
    print(MAP(2, 1), s_area, ATTR_W);
    print(MAP(2, 19), s_chain, ATTR_W);
    PROF(25);
    put_score(MAP(1, 7), score, ATTR_Y);
    PROF(26);
    put_dec2(MAP(1, 25), stage, ATTR_Y);
    put_dec2(MAP(2, 6), pct, ATTR_Y);
    put_dec2(MAP(2, 10), (uint8_t)goal, ATTR_Y);
    uint16_t at = MAP(2, 14);
    bg3map[at++] = cell(ATTR_P, TILE_HEART);
    put_digit(at, lives, ATTR_Y);
    put_dec2(MAP(2, 25), chain, ATTR_O);
    PROF(27);
    draw_owned(0);
    PROF(28);
    chain_bar = CHAIN_BAR_REDRAW;
    draw_chain_bar();
    bg3_dirty = 1;
}

/* 4-cell bar at row 2, col 28: time left before the chain breaks */
void draw_chain_bar(void)
{
    uint8_t cells = 0;
    if (chain)
        cells = hw_div8(chain_t + 149, 150);      /* rounds up: 0..4 */
    if (cells == chain_bar)
        return;
    chain_bar = cells;

    uint8_t attr = cells >= 2 ? ATTR_O : ATTR_P;  /* pink when nearly out */
    uint16_t at = MAP(2, 28);
    for (small_t i = 0; i < CHAIN_BAR_MAX; i++, at++)
        bg3map[at] = i < cells ? cell(attr, TILE_BAR) : 0;
    bg3_dirty = 1;
}

/* owned perks as an 8x8 icon, plus the stack count from 2 up */
void draw_owned(uint8_t row)
{
    clear_row(row);
    uint16_t *at = &bg3map[MAP(row, 0)];
    for (small_t p = 0; p < PERK_COUNT; p++) {
        small_t n = run_perks.stacks[p];
        if (!n)
            continue;
        at[0] = cell(ATTR_W, 120 + p);
        if (n >= 2)
            at[1] = cell(ATTR_Y, 16 + (n & 0x0F));
        at += 2;
    }
}

/* ---- messages ------------------------------------------------------------ */

void show_msg(const char *s)
{
    clear_row(ROW_MSG);
    print(MAP(ROW_MSG, 2), s, ATTR_Y);
    msg_timer = MSG_FRAMES;
}

void hud_update(void)
{
    if (msg_timer && --msg_timer == 0)
        clear_row(ROW_MSG);

    if (!chain)
        return;
    if (chain_t == 0) {
        chain = 0;
        draw_hud();
        show_msg(s_broken);
        sfx(CH_TONE, sfx_tick);
    } else {
        chain_t--;
        draw_chain_bar();
    }
}
