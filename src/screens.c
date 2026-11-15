/* The screens: title, draft, ready, play, pause, dying, clear, game over. */
#include "game.h"
#include "hw.h"

static const char s_paused[] = "PAUSED";
static const char s_clear[]  = "STAGE CLEAR!";
static const char s_bonus[]  = "BONUS";
static const char s_over[]   = "GAME OVER";
static const char s_press[]  = "PRESS START";
static const char s_sub[]    = "RECLAIM THE NEBULA";
static const char s_help1[]  = "HOLD B AND MOVE TO CUT";
static const char s_help2[]  = "CLAIM 80% OF THE FIELD";
static const char s_hi[]     = "HI";
static const char s_common[] = "COMMON";
static const char s_special[] = "SPECIAL";
static const char s_rare[]   = "RARE";
static const char s_own[]    = "OWN ";
static const char s_choose[] = "CHOOSE A PERK";
static const char s_forstage[] = "FOR STAGE";
static const char s_yours[]  = "YOUR PERKS";
static const char s_dhelp[]  = "LEFT/RIGHT CHOOSE  B TAKE";
static const char s_reroll[] = "SELECT: REROLL";

enum {
    TILE_CARD_FRAME = 170,
    TILE_DRAFT_BG   = 85,
    ATTR_DRAFT_BG   = 0x08,          /* BG1 high byte of the draft backdrop */
    CARD_SELECTED   = 0x10,          /* gold palette, frame and inside */
    CARD_INSIDE     = 0x08,
    CARD_ROW0 = 5, CARD_ROW1 = 21, CARD_W = 9,
    DRAFT_TIMER = 40, READY_INVULN = 120, DYING_FRAMES = 90,
    CLEAR_FRAMES = 240, OVER_FRAMES = 300, OVER_INPUT_AT = 200,
    LOGO_W = 18, LOGO_H = 3,
    GOAL_BONUS_UNITS = 100, FLAT_BONUS_UNITS = 50,
    TM_STAGE = 0x17, TM_NO_BG1 = 0x16,
    BTN_TAKE = BTN_B | BTN_Y | BTN_START | BTN_A
};

/* BG1 high byte of a card frame, by perk rarity */
static const uint8_t rar_pal[3]  = { 0x08, 0x14, 0x18 };
static const uint8_t rar_attr[3] = { ATTR_W, ATTR_G, ATTR_P };
static const char *const rar_str[3] = { s_common, s_special, s_rare };

/* forced blank off again: the tail of every loader (PORTING.md rule 6) */
static void display_on(uint8_t tm)
{
    tm_val = tm;
    TM = tm;
    bg1_dirty = 0;
    bg3_dirty = 0;
    bright = 0x0F;
    INIDISP = 0x0F;
    (void)RDNMI;
    NMITIMEN = 0x81;
}

static void display_off(void)
{
    INIDISP = 0x80;
    NMITIMEN = 0;
}

/* ---- title --------------------------------------------------------------- */

void enter_title(void)
{
    display_off();
    load_picture(0);
    clear_bg3();
    for (small_t r = 0; r < LOGO_H; r++)
        for (small_t c = 0; c < LOGO_W; c++)
            bg3map[MAP(4 + r, 7) + c] = title_map[r * LOGO_W + c];
    print(MAP(9, 7), s_sub, ATTR_W);
    print(MAP(21, 5), s_help1, ATTR_W);
    print(MAP(23, 5), s_help2, ATTR_W);
    print(MAP(25, 9), s_hi, ATTR_Y);
    put_score(MAP(25, 12), hiscore, ATTR_Y);
    upload_bg3();
    build_oam(ST_TITLE);
    upload_oam();
    display_on(0x16);
}

void st_title(void)
{
    /* blink PRESS START: on 32 frames, off 32 */
    uint8_t n = nmi_count;
    if ((n & 0x1F) == 0) {
        if (n & 0x20)
            clear_row(18);
        else
            print(MAP(18, 10), s_press, ATTR_Y);
    }

    if (!(joy_new & BTN_START))
        return;
    rng = (rng ^ nmi_count) | 1;            /* seed from the press time */
    score = 0;
    lives = 3;
    stage = 1;
    new_run();
    goto_state(ST_DRAFT);
}

/* ---- draft ----------------------------------------------------------------- */

static void draw_cards(void)
{
    for (small_t i = 0; i < 3; i++) {
        small_t col0 = 1 + 10 * i;
        uint16_t frame = rar_pal[perk_cards[offers[i]].rarity];
        uint16_t inside = CARD_INSIDE;
        if (i == cursor)
            frame = inside = CARD_SELECTED;
        frame = (frame << 8) | TILE_CARD_FRAME;
        inside <<= 8;                               /* tile 0 */

        for (small_t r = CARD_ROW0; r <= CARD_ROW1; r++) {
            uint16_t at = MAP(r, col0);
            for (small_t c = 0; c < CARD_W; c++) {
                small_t edge = r == CARD_ROW0 || r == CARD_ROW1 || c == 0 || c == CARD_W - 1;
                bg1map[at + c] = edge ? frame : inside;
            }
        }
    }
    bg1_dirty = 1;
}

/* name, description, owned count and rarity of card i */
static void card_text(small_t i)
{
    small_t p = offers[i];
    const perk_card *pc = &perk_cards[p];
    small_t col = 2 + 10 * i;

    print(MAP(11, col), pc->name, ATTR_Y);
    for (small_t l = 0; l < 4; l++)
        print(MAP(13 + l, col), pc->text[l], ATTR_W);

    small_t owned = run_perks.stacks[p];
    if (owned) {
        uint16_t at = print(MAP(18, col), s_own, ATTR_G);
        put_digit(at, owned, ATTR_G);
    }
    print(MAP(20, col), rar_str[pc->rarity], rar_attr[pc->rarity]);
}

static void all_card_text(void)
{
    for (small_t i = 0; i < 3; i++)
        card_text(i);
    clear_row(27);
    if (rerolls)
        print(MAP(27, 8), s_reroll, ATTR_G);
}

void enter_draft(void)
{
    display_off();
    music_stop();
    cursor = 0;
    timer = DRAFT_TIMER;
    shake_t = 0;
    fl_r = fl_g = fl_b = 0;
    juice_update();
    gen_offers();
    rerolls = 1;

    for (uint16_t i = 0; i < 1024; i++)
        bg1map[i] = TILE_DRAFT_BG | (ATTR_DRAFT_BG << 8);
    draw_cards();

    clear_bg3();
    print(MAP(1, 9), s_choose, ATTR_Y);
    print(MAP(2, 10), s_forstage, ATTR_W);
    put_dec2(MAP(2, 20), stage, ATTR_W);
    all_card_text();
    if (run_perks.total) {
        print(MAP(23, 11), s_yours, ATTR_W);
        draw_owned(24);
    }
    print(MAP(26, 3), s_dhelp, ATTR_W);

    upload_bg1();
    upload_bg3();
    build_oam(ST_DRAFT);
    upload_oam();
    display_on(TM_STAGE);
    sfx(CH_JINGLE, jingle_draft);
}

void st_draft(void)
{
    if (timer)
        timer--;

    if (joy_new & BTN_LEFT) {
        cursor = cursor ? cursor - 1 : 2;
        draw_cards();
        sfx(CH_TONE, sfx_tick);
    }
    if (joy_new & BTN_RIGHT) {
        cursor = cursor == 2 ? 0 : cursor + 1;
        draw_cards();
        sfx(CH_TONE, sfx_tick);
    }
    if ((joy_new & BTN_SELECT) && rerolls) {
        rerolls--;
        gen_offers();
        draw_cards();
        for (small_t r = 11; r < 21; r++)
            clear_row(r);
        all_card_text();
        sfx(CH_TONE, sfx_item);
    }

    if (timer == 0 && (joy_new & BTN_TAKE)) {
        take_offer();
        goto_state(ST_READY);
        sfx(CH_JINGLE, jingle_start);
    }
}

/* ---- ready, play, pause ----------------------------------------------------- */

void st_ready(void)
{
    if (--timer == 0)
        goto_state(ST_PLAY);
}

void enter_play(void)
{
    clear_row(13);
    clear_row(14);
    clear_row(15);
    loadout_rebuild(&run_perks);        /* stacks bought during READY count */
    music_start();
}

static void timers_update(void)
{
    if (invuln) invuln--;
    if (shield) shield--;
    if (freeze) freeze--;
    hud_update();
}

void st_play(void)
{
    if (joy_new & BTN_START) {
        goto_state(ST_PAUSE);
        return;
    }
    PROF(16);
    player_update();
    calc_ppos();
    PROF(17);
    if (state == ST_PLAY) {
        enemies_update();
        PROF(18);
        timers_update();
    }
    PROF(19);
    booms_update();
    PROF(20);
#ifdef PROFILE
    if (prof_bench == 1) {          /* micro-benchmarks, set by hand from a tool */
        PROF(21);
        (void)enemy_box_flags(0);   /* the boss box */
        PROF(22);
        enemies_update();
        PROF(23);
        (void)enemy_box_flags(1);   /* a shard box */
        PROF(29);
    }
    if (prof_bench == 2) {          /* tools/test_selftest.py: one batch */
        selftest_box_scan(200);
        prof_bench = 0;
    }
    if (prof_bench == 3) {          /* tools/test_selftest.py */
        selftest_numbers(50);
        prof_bench = 0;
    }
#endif
}

void enter_pause(void)
{
    print(MAP(14, 13), s_paused, ATTR_Y);
    music_stop();
}

void st_pause(void)
{
    if (joy_new & BTN_START)
        goto_state(ST_PLAY);
}

/* ---- dying -------------------------------------------------------------------- */

void enter_dying(void)
{
    chain = 0;
    draw_chain_bar();
    flash(18, 3, 3);
    shake_t = 24;
    timer = DYING_FRAMES;
    spawn_boom(ppx, ppy);
    music_stop();
    sfx(CH_NOISE, sfx_death);
}

void st_dying(void)
{
    booms_update();
    if (--timer)
        return;
    PROF(7);
    wipe_trail();
    PROF(15);
    lives--;
    draw_hud();
    PROF(30);
    if (lives == 0) {
        goto_state(ST_OVER);
        return;
    }
    invuln = READY_INVULN;
    goto_state(ST_PLAY);
}

/* ---- stage clear ---------------------------------------------------------------- */

void enter_clear(void)
{
    music_stop();
    timer = CLEAR_FRAMES;
    tm_val = TM_NO_BG1;

    /* bonus in units of 10: 1000 points per percent over the goal, plus 500,
     * times (1 + MIDAS stacks) */
    uint8_t over_goal = pct - (uint8_t)goal;
    uint16_t base = hw_mul8(over_goal, GOAL_BONUS_UNITS) + FLAT_BONUS_UNITS;
    uint32_t bonus = mul16x8(base, 1 + run_perks.stacks[PERK_MIDAS]);
    score += bonus;

    shake_t = 0;
    flash(20, 20, 20);
    draw_hud();
    print(MAP(12, 10), s_clear, ATTR_Y);
    print(MAP(15, 9), s_bonus, ATTR_W);
    uint16_t at = put_num(MAP(15, 16), bonus, ATTR_Y);
    put_digit(at, 0, ATTR_Y);
    sfx(CH_JINGLE, jingle_clear);
}

void st_clear(void)
{
    if (--timer)
        return;
    if (stage < 99)
        stage++;
    goto_state(ST_DRAFT);
}

/* ---- game over ------------------------------------------------------------------ */

void enter_gameover(void)
{
    timer = OVER_FRAMES;
    print(MAP(14, 11), s_over, ATTR_Y);
    if (score >= hiscore)
        hiscore = score;
    sfx(CH_JINGLE, jingle_over);
}

void st_over(void)
{
    --timer;
    if (timer == 0 || (timer < OVER_INPUT_AT && (joy_new & BTN_START)))
        goto_state(ST_TITLE);
}
