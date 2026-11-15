#include "perks.h"

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

void loadout_clear(loadout *l)
{
    for (unsigned p = 0; p < PERK_COUNT; p++)
        l->stacks[p] = 0;
    l->total = 0;
    l->n_scorers = 0;
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
