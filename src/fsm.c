/* The game-flow and player-mode state machines (modelled in spec/GameFSM.tla).
 *
 *  Game flow                          Player mode (only during a stage)
 *    BOOT  -> TITLE                     EDGE    -> DRAW     cut starts
 *    TITLE -> DRAFT     start           DRAW    -> RETRACT  cut button released
 *    DRAFT -> READY     perk taken      RETRACT -> DRAW     pressed again
 *    READY -> PLAY      timer           RETRACT -> EDGE     trail fully retracted
 *    PLAY  -> PAUSE     start           DRAW    -> EDGE     cut closed (filled)
 *    PAUSE -> PLAY      start           any     -> EDGE     trail wiped (hit)
 *    PLAY  -> DYING     hit, no AEGIS
 *    PLAY  -> CLEAR     goal reached    invariant: pmode = EDGE <=> trail_len = 0
 *    DYING -> PLAY      lives left
 *    DYING -> OVER      no lives        A handler that changes state must return
 *    CLEAR -> DRAFT     timer           straight away (st_play re-checks `state`
 *    OVER  -> TITLE     timer / start   after the player moves).
 *
 * goto_state() and set_pmode() are the only writers of `state` and `pmode`
 * (besides the boot value and the per-stage reset). An illegal transition is
 * still taken, so the game keeps running, but it is counted in fsm_errs with
 * the offending pair; the test tools assert it stays at zero.
 */
#include "game.h"

uint8_t state = ST_BOOT;
uint8_t pmode;
uint8_t fsm_errs, fsm_kind, fsm_from, fsm_to;

#define FROM(s) (1u << (s))

/* the states each state may be entered from */
static const uint16_t allowed_from[ST_COUNT] = {
    [ST_TITLE] = FROM(ST_BOOT) | FROM(ST_OVER),
    [ST_READY] = FROM(ST_DRAFT),
    [ST_PLAY]  = FROM(ST_READY) | FROM(ST_PAUSE) | FROM(ST_DYING),
    [ST_DYING] = FROM(ST_PLAY),
    [ST_CLEAR] = FROM(ST_PLAY),
    [ST_OVER]  = FROM(ST_DYING),
    [ST_DRAFT] = FROM(ST_TITLE) | FROM(ST_CLEAR),
    [ST_PAUSE] = FROM(ST_PLAY),
};

static void (*const entry_action[ST_COUNT])(void) = {
    [ST_TITLE] = enter_title,  [ST_READY] = load_stage,
    [ST_PLAY]  = enter_play,   [ST_DYING] = enter_dying,
    [ST_CLEAR] = enter_clear,  [ST_OVER]  = enter_gameover,
    [ST_DRAFT] = enter_draft,  [ST_PAUSE] = enter_pause,
};

static void (*const per_frame[ST_COUNT])(void) = {
    [ST_TITLE] = st_title,  [ST_READY] = st_ready,
    [ST_PLAY]  = st_play,   [ST_DYING] = st_dying,
    [ST_CLEAR] = st_clear,  [ST_OVER]  = st_over,
    [ST_DRAFT] = st_draft,  [ST_PAUSE] = st_pause,
};

static const uint8_t pm_allowed_from[3] = {
    [PM_EDGE]    = FROM(PM_EDGE) | FROM(PM_DRAW) | FROM(PM_RETRACT),
    [PM_DRAW]    = FROM(PM_EDGE) | FROM(PM_RETRACT),
    [PM_RETRACT] = FROM(PM_DRAW),
};

static void fault(uint8_t kind, uint8_t from, uint8_t to)
{
    fsm_kind = kind;
    fsm_from = from;
    fsm_to = to;
    if (fsm_errs != 0xFF)
        fsm_errs++;
}

void goto_state(uint8_t to)
{
    if (!(allowed_from[to] & FROM(state)))
        fault(1, state, to);
    /* The entry action runs in the old state, and `state` changes only once
     * it has finished: a multi-frame entry (forced-blank loads) is never seen
     * half-done. */
    entry_action[to]();
    state = to;
}

void set_pmode(uint8_t to)
{
    if (!(pm_allowed_from[to] & FROM(pmode)))
        fault(2, pmode, to);
    pmode = to;
}

void fsm_check(void)
{
    if (state == ST_TITLE || state == ST_DRAFT || state == ST_OVER)
        return;
    if ((trail_len == 0) != (pmode == PM_EDGE))
        fault(3, state, pmode);
}

void run_state(void)
{
    per_frame[state]();
}
