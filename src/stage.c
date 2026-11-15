/* New run and stage setup (legacy new_run, load_stage, init_entities). */
#include "game.h"
#include "hw.h"

uint16_t timer;
uint8_t  lives, stage, pct;
uint16_t goal;
uint16_t claimed;
uint32_t score, hiscore;
uint16_t invuln, shield, freeze, msg_timer;

#define BASE_GOAL      80        /* percent needed with no QUOTA perk */
#define QUOTA_STEP     5         /* percent each QUOTA stack takes off */
#define START_IDX      (47 * 64 + 30)   /* bottom edge, middle */
#define START_INVULN   90
#define START_CHAIN_T  600
#define READY_FRAMES   120
#define TM_ALL         0x17      /* BG1, BG2, BG3 and sprites */

void new_run(void)
{
    loadout_clear(&run_perks);
    offers[0] = offers[1] = offers[2] = 0;
    cursor = 0;
    rerolls = 0;
    chain = 0;
    chain_t = 0;
    kills = 0;
    aegis_left = 0;
    stage_mult = 0;
    last_mult = 0;
    goal = BASE_GOAL;
}

void init_entities(void)
{
    p_idx = START_IDX;
    pmode = PM_EDGE;             /* per-stage FSM reset: every stage starts on the edge */
    trail_len = 0;
    pspeed = run_perks.stacks[PERK_SWIFT] ? 1 : 2;
    pmove_timer = 1;
    shield = 0;
    freeze = 0;
    msg_timer = 0;
    invuln = START_INVULN;
    kills = 0;
    chain_t = START_CHAIN_T;
    shake_t = 0;
    fl_r = fl_g = fl_b = 0;
    aegis_left = run_perks.stacks[PERK_AEGIS];
    stage_mult = 0;
    goal = BASE_GOAL - QUOTA_STEP * run_perks.stacks[PERK_QUOTA];

    enemies_init();
    loadout_rebuild(&run_perks);
}

void load_stage(void)
{
    INIDISP = 0x80;
    NMITIMEN = 0;

    load_picture((stage - 1) & 3);
    field_init();
    field_redraw_all();
    upload_bg1();
    claimed = 0;
    pct = 0;
    init_entities();

    clear_bg3();
    draw_hud();
    print(MAP(13, 12), "STAGE", ATTR_Y);
    put_dec2(MAP(13, 18), stage, ATTR_Y);
    print(MAP(15, 12), "READY!", ATTR_W);
    upload_bg3();

    timer = READY_FRAMES;
    calc_ppos();
    build_oam(ST_READY);
    upload_oam();
    tm_val = TM_ALL;
    TM = TM_ALL;
    bg1_dirty = 0;
    bg3_dirty = 0;

    bright = 0x0F;
    INIDISP = 0x0F;
    (void)RDNMI;
    NMITIMEN = 0x81;
}
