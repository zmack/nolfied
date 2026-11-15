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

uint16_t print(uint16_t at, const char *s, uint8_t attr)
{
    for (; *s; s++)
        bg3map[at++] = cell(attr, (uint8_t)(*s - 32));
    bg3_dirty = 1;
    return at;
}

uint16_t put_digit(uint16_t at, uint8_t d, uint8_t attr)
{
    bg3map[at] = cell(attr, 16 + (d & 0x0F));
    return at + 1;
}

uint16_t put_dec2(uint16_t at, uint8_t v, uint8_t attr)
{
    uint16_t tens = hw_div8(v, 10);
    uint8_t ones = RDMPY;
    at = put_digit(at, tens, attr);
    return put_digit(at, ones, attr);
}

/* four decimal digits of v (0..9999), least significant first */
static void split4(uint16_t v, uint8_t *d)
{
    uint16_t q = hw_div8(v, 10);
    d[0] = RDMPY;
    uint16_t q2 = hw_div8(q, 10);
    d[1] = RDMPY;
    d[3] = hw_div8(q2, 10);
    d[2] = RDMPY;
}

/* all ten decimal digits of v, least significant first */
static void digits(uint32_t v, uint8_t *d)
{
    uint16_t r0, r1, top;
    if (v < 0x10000UL) {
        uint16_t a = (uint16_t)v;
        r1 = a / 10000;
        r0 = a % 10000;
        top = 0;
    } else {
        uint32_t q = v / 10000;
        r0 = (uint16_t)(v - q * 10000);
        top = (uint16_t)(q / 10000);
        r1 = (uint16_t)(q - (uint32_t)top * 10000);
    }
    split4(r0, d);
    split4(r1, d + 4);
    d[8] = top % 10;
    d[9] = top / 10;
}

uint16_t put_num(uint16_t at, uint32_t v, uint8_t attr)
{
    uint8_t d[10];
    digits(v, d);
    uint_fast8_t n = 10;
    while (n > 1 && d[n - 1] == 0)
        n--;
    while (n)
        at = put_digit(at, d[--n], attr);
    return at;
}

/* the score is kept in tens: print 7 digits, then the fixed trailing zero */
uint16_t put_score(uint16_t at, uint32_t units, uint8_t attr)
{
    uint8_t d[10];
    digits(units, d);
    for (uint_fast8_t n = 7; n; )
        at = put_digit(at, d[--n], attr);
    return put_digit(at, 0, attr);
}

void clear_row(uint8_t row)
{
    uint16_t at = row * 32;
    for (uint_fast8_t i = 32; i; i--)
        bg3map[at++] = 0;
    bg3_dirty = 1;
}

void clear_bg3(void)
{
    for (uint16_t i = 0; i < 1024; i++)
        bg3map[i] = 0;
    bg3_dirty = 1;
}

/* ---- HUD --------------------------------------------------------------- */

void draw_hud(void)
{
    print(MAP(1, 1), s_score, ATTR_W);
    print(MAP(1, 19), s_stage, ATTR_W);
    print(MAP(2, 1), s_area, ATTR_W);
    print(MAP(2, 19), s_chain, ATTR_W);

    put_score(MAP(1, 7), score, ATTR_Y);
    put_dec2(MAP(1, 25), stage, ATTR_Y);
    put_dec2(MAP(2, 6), pct, ATTR_Y);
    put_dec2(MAP(2, 10), (uint8_t)goal, ATTR_Y);
    uint16_t at = MAP(2, 14);
    bg3map[at++] = cell(ATTR_P, TILE_HEART);
    put_digit(at, lives, ATTR_Y);
    put_dec2(MAP(2, 25), chain, ATTR_O);

    draw_owned(0);
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
    for (uint_fast8_t i = 0; i < CHAIN_BAR_MAX; i++, at++)
        bg3map[at] = i < cells ? cell(attr, TILE_BAR) : 0;
    bg3_dirty = 1;
}

/* owned perks as an 8x8 icon, plus the stack count from 2 up */
void draw_owned(uint8_t row)
{
    clear_row(row);
    uint16_t at = row * 32;
    for (uint_fast8_t p = 0; p < PERK_COUNT; p++) {
        uint_fast8_t n = run_perks.stacks[p];
        if (!n)
            continue;
        bg3map[at++] = cell(ATTR_W, 120 + p);
        if (n >= 2)
            put_digit(at, n, ATTR_Y);
        at++;
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
