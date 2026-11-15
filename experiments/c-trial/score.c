#include "score.h"
#include "hw_math.h"

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
