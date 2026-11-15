/* Chips x mult scoring of a claim (the C trial's module, now the game's). */
#include "game.h"
#include "hw.h"

uint8_t  chain;
uint16_t chain_t;
uint8_t  kills;
uint8_t  aegis_left;
uint16_t stage_mult;
uint16_t last_mult;

#define CHAIN_FRAMES 600            /* 10 seconds to make the next claim */

static inline uint16_t fold_mult(const claim *c, const loadout *l)
{
    /* base: 1, plus one per chain link, plus what this stage has banked */
    mult m = { 1 + c->chain + c->stage_mult, 1 };

    const scorer *s = l->scorers;
    for (unsigned i = l->n_scorers; i; i--, s++) {
        uint_fast8_t n = s->stacks;
        switch (s->id) {
#define SCORING(id, name, t1, t2, t3, t4, max, rarity, effect) \
        case PERK_##id: effect; break;
/* passive perks never reach here, but listing every id keeps the cases dense,
 * so the compiler emits a jump table instead of a slow search */
#define PASSIVE(id, name, t1, t2, t3, t4, max, rarity) \
        case PERK_##id: break;
#include "perk_defs.h"
#undef SCORING
#undef PASSIVE
        }
    }

    uint32_t total = m.times == 1 ? m.plus : mul16x8(m.plus, m.times);
    return total > MULT_CAP ? MULT_CAP : (uint16_t)total;
}

uint16_t claim_mult(const claim *c, const loadout *l)
{
    return fold_mult(c, l);
}

uint32_t claim_points(const claim *c, const loadout *l, uint16_t *mult_out)
{
    uint16_t m = fold_mult(c, l);
    if (mult_out)
        *mult_out = m;
    return mul16x16(c->chips, m);
}

/* "220 X 12 = +26400" under the field, coloured by how big the mult is */
static void popup(uint16_t chips, uint16_t m, uint32_t points)
{
    uint8_t attr = m >= 50 ? ATTR_P : m >= 10 ? ATTR_O : ATTR_Y;
    clear_row(27);
    uint16_t at = MAP(27, 1);
    at = put_num(at, chips, attr);
    at = print(at, " X ", attr);
    at = put_num(at, m, attr);
    at = print(at, " = +", attr);
    at = put_num(at, points, attr);
    put_digit(at, 0, attr);                 /* score is kept in tens */
    msg_timer = 180;
}

void score_claim(uint16_t chips)
{
    claim c = {
        .chips = chips, .chain = chain, .kills = kills,
        .perks_owned = run_perks.total, .stage_mult = stage_mult,
    };
    uint32_t points = claim_points(&c, &run_perks, &last_mult);
    score += points;
    popup(chips, last_mult, points);

    if (chain < 99)
        chain++;
    chain_t = CHAIN_FRAMES;
    draw_chain_bar();

    /* juice: shake grows with the claim, the flash with the multiplier */
    uint16_t big = chips >> 6;
    shake_t = 6 + (big > 14 ? 14 : big);
    uint16_t hot = last_mult >> 2;
    uint8_t f = 4 + (hot > 14 ? 14 : hot);
    flash(f, f, f);

    /* STASIS: freeze the enemies for 1.5 s per stack */
    uint8_t stasis = run_perks.stacks[PERK_STASIS];
    if (stasis) {
        uint16_t t = hw_mul8(stasis, 90);
        if (t > freeze)
            freeze = t;
    }
}
