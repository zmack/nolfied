#include "perks.h"
#include "hw_math.h"

#define BIG_CLAIM   150
#define TINY_CLAIM   40

/* ---- scoring hooks: one small function per perk that touches the multiplier */

static void greed(const claim *c, uint_fast8_t n, mult *m)  { (void)c; m->plus += 2 * n; }
static void chain(const claim *c, uint_fast8_t n, mult *m)  { m->plus += hw_mul8(c->chain, n); }
static void sniper(const claim *c, uint_fast8_t n, mult *m) { if (c->chips < TINY_CLAIM) m->plus += 6 * n; }
static void hunter(const claim *c, uint_fast8_t n, mult *m) { m->plus += 3 * hw_mul8(n, c->kills); }
static void prism(const claim *c, uint_fast8_t n, mult *m)  { m->plus += hw_mul8(n, c->perks_owned); }
static void titan(const claim *c, uint_fast8_t n, mult *m)  { if (c->chips >= BIG_CLAIM) m->times *= 1 + n; }
static void glass(const claim *c, uint_fast8_t n, mult *m)  { (void)c; (void)n; m->times *= 3; }

/* ---- the deck: card data (cold, draft screen only) ------------------- */

const perk_card perk_cards[PERK_COUNT] = {
    [PERK_GREED]   = { "GREED",   {"+2 MULT", "EVERY",   "CLAIM",   ""},        9, RARITY_COMMON  },
    [PERK_CHAIN]   = { "CHAIN",   {"CHAIN",   "LINKS",   "+1 MULT", "MORE"},    5, RARITY_COMMON  },
    [PERK_TITAN]   = { "TITAN",   {"X2 MULT", "ON BIG",  "CLAIMS",  "(150+)"},  3, RARITY_SPECIAL },
    [PERK_SNIPER]  = { "SNIPER",  {"+6 MULT", "ON TINY", "CLAIMS",  "(<40)"},   5, RARITY_COMMON  },
    [PERK_HUNTER]  = { "HUNTER",  {"+3 MULT", "PER",     "SHARD",   "KILLED"},  5, RARITY_COMMON  },
    [PERK_SWIFT]   = { "SWIFT",   {"MOVE",    "FASTER",  "",        ""},        1, RARITY_COMMON  },
    [PERK_AEGIS]   = { "AEGIS",   {"BLOCK",   "1 HIT",   "EACH",    "STAGE"},   3, RARITY_SPECIAL },
    [PERK_STASIS]  = { "STASIS",  {"CLAIMS",  "FREEZE",  "FOES",    "1.5 SEC"}, 3, RARITY_COMMON  },
    [PERK_CHRONO]  = { "CHRONO",  {"FOES",    "MOVE",    "20%",     "SLOWER"},  3, RARITY_SPECIAL },
    [PERK_PHOENIX] = { "PHOENIX", {"+1 LIFE", "",        "",        ""},        9, RARITY_SPECIAL },
    [PERK_LUCKY]   = { "LUCKY",   {"+1",      "CAPSULE", "EACH",    "STAGE"},   2, RARITY_COMMON  },
    [PERK_PRISM]   = { "PRISM",   {"+1 MULT", "PER",     "PERK",    "OWNED"},   5, RARITY_RARE    },
    [PERK_GLASS]   = { "GLASS",   {"X3 MULT", "BUT",     "-1 LIFE", ""},        1, RARITY_RARE    },
    [PERK_QUOTA]   = { "QUOTA",   {"GOAL",    "-5%",     "",        ""},        3, RARITY_SPECIAL },
    [PERK_JACKPOT] = { "JACKPOT", {"CAPSULE", "GIVES",   "+4 MULT", "(STAGE)"}, 5, RARITY_COMMON  },
    [PERK_MIDAS]   = { "MIDAS",   {"STAGE",   "BONUS",   "X2",      ""},        3, RARITY_SPECIAL },
};

/* ---- scoring hooks (hot): perks not listed leave the multiplier alone -- */

const mult_hook perk_on_claim[PERK_COUNT] = {
    [PERK_GREED]  = greed,
    [PERK_CHAIN]  = chain,
    [PERK_TITAN]  = titan,
    [PERK_SNIPER] = sniper,
    [PERK_HUNTER] = hunter,
    [PERK_PRISM]  = prism,
    [PERK_GLASS]  = glass,
};

/* ---- the loadout ------------------------------------------------------- */

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
    if (!perk_on_claim[p])
        return;
    for (unsigned i = 0; i < l->n_scorers; i++) {
        if (l->scorers[i].hook == perk_on_claim[p]) {
            l->scorers[i].stacks = l->stacks[p];
            return;
        }
    }
    l->scorers[l->n_scorers].hook = perk_on_claim[p];
    l->scorers[l->n_scorers].stacks = l->stacks[p];
    l->n_scorers++;
}
