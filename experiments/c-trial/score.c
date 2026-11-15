#include "score.h"

uint16_t claim_mult(const claim *c, const uint8_t stacks[PERK_COUNT])
{
    /* base: 1, plus one per chain link, plus what this stage has banked */
    mult m = { 1 + c->chain + c->stage_mult, 1 };

    for (uint8_t p = 0; p < PERK_COUNT; p++) {
        if (stacks[p] && perk_table[p].on_claim)
            perk_table[p].on_claim(c, stacks[p], &m);
    }

    uint32_t total = (uint32_t)m.plus * m.times;
    return total > MULT_CAP ? MULT_CAP : (uint16_t)total;
}

uint32_t claim_points(const claim *c, const uint8_t stacks[PERK_COUNT], uint16_t *mult_out)
{
    uint16_t m = claim_mult(c, stacks);
    if (mult_out)
        *mult_out = m;
    return (uint32_t)c->chips * m;
}
