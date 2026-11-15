/* The perk deck, the loadout, and draft offers. */
#include "game.h"

const perk_card perk_cards[PERK_COUNT] = {
#define SCORING(id, name, t1, t2, t3, t4, max, rarity, effect) \
    [PERK_##id] = { name, { t1, t2, t3, t4 }, max, RARITY_##rarity },
#define PASSIVE(id, name, t1, t2, t3, t4, max, rarity) \
    [PERK_##id] = { name, { t1, t2, t3, t4 }, max, RARITY_##rarity },
#include "perk_defs.h"
#undef SCORING
#undef PASSIVE
};

static const uint8_t is_scoring[PERK_COUNT] = {
#define SCORING(id, name, t1, t2, t3, t4, max, rarity, effect) [PERK_##id] = 1,
#define PASSIVE(id, name, t1, t2, t3, t4, max, rarity)         [PERK_##id] = 0,
#include "perk_defs.h"
#undef SCORING
#undef PASSIVE
};

const uint8_t rarity_weight[3] = { 4, 2, 1 };

loadout  run_perks;
uint8_t  offers[3];
uint16_t cursor;
uint8_t  rerolls;

/* ---- the loadout --------------------------------------------------------- */

void loadout_clear(loadout *l)
{
    for (unsigned p = 0; p < PERK_COUNT; p++)
        l->stacks[p] = 0;
    l->total = 0;
    l->n_scorers = 0;
}

void loadout_rebuild(loadout *l)
{
    l->n_scorers = 0;
    for (unsigned p = 0; p < PERK_COUNT; p++) {
        if (l->stacks[p] && is_scoring[p]) {
            l->scorers[l->n_scorers].id = p;
            l->scorers[l->n_scorers].stacks = l->stacks[p];
            l->n_scorers++;
        }
    }
}

void loadout_take(loadout *l, perk_id p)
{
    l->stacks[p]++;
    l->total++;
    if (!is_scoring[p])
        return;
    for (unsigned i = 0; i < l->n_scorers; i++) {
        if (l->scorers[i].id == p) {
            l->scorers[i].stacks = l->stacks[p];
            return;
        }
    }
    l->scorers[l->n_scorers].id = p;
    l->scorers[l->n_scorers].stacks = l->stacks[p];
    l->n_scorers++;
}

/* ---- the draft ------------------------------------------------------------- */

/* can perk p still be offered (not maxed, not already on the table)? */
static int offerable(unsigned p)
{
    if (run_perks.stacks[p] >= perk_cards[p].max_stacks)
        return 0;
    return p != offers[0] && p != offers[1] && p != offers[2];
}

/* three distinct perks, weighted by rarity */
void gen_offers(void)
{
    offers[0] = offers[1] = offers[2] = 0xFF;
    for (unsigned k = 0; k < 3; k++) {
        unsigned total = 0;
        for (unsigned p = 0; p < PERK_COUNT; p++)
            if (offerable(p))
                total += rarity_weight[perk_cards[p].rarity];
        uint8_t pick = PERK_PHOENIX;            /* fallback if all are maxed */
        if (total) {
            unsigned r = rand16() & 0xFF;
            while (r >= total)
                r -= total;
            for (unsigned p = 0; p < PERK_COUNT; p++) {
                if (!offerable(p))
                    continue;
                unsigned w = rarity_weight[perk_cards[p].rarity];
                if (r < w) { pick = p; break; }
                r -= w;
            }
        }
        offers[k] = pick;
    }
}

void take_offer(void)
{
    perk_id p = (perk_id)offers[cursor];
    loadout_take(&run_perks, p);
    if (p == PERK_PHOENIX && lives < 9)
        lives++;
    if (p == PERK_GLASS && lives > 1)
        lives--;
}
