#include "perks.h"

#define BIG_CLAIM   150
#define TINY_CLAIM   40

/* ---- scoring hooks: one small function per perk that touches the multiplier */

static void greed(const claim *c, uint8_t n, mult *m)  { (void)c; m->plus += 2 * n; }
static void chain(const claim *c, uint8_t n, mult *m)  { m->plus += (uint16_t)c->chain * n; }
static void sniper(const claim *c, uint8_t n, mult *m) { if (c->chips < TINY_CLAIM) m->plus += 6 * n; }
static void hunter(const claim *c, uint8_t n, mult *m) { m->plus += 3 * n * c->kills; }
static void prism(const claim *c, uint8_t n, mult *m)  { m->plus += (uint16_t)n * c->perks_owned; }
static void titan(const claim *c, uint8_t n, mult *m)  { if (c->chips >= BIG_CLAIM) m->times *= 1 + n; }
static void glass(const claim *c, uint8_t n, mult *m)  { (void)c; (void)n; m->times *= 3; }

/* ---- the deck ---------------------------------------------------------- */

const perk_def perk_table[PERK_COUNT] = {
    [PERK_GREED]   = { "GREED",   {"+2 MULT", "EVERY",   "CLAIM",   ""},        9, RARITY_COMMON,  greed  },
    [PERK_CHAIN]   = { "CHAIN",   {"CHAIN",   "LINKS",   "+1 MULT", "MORE"},    5, RARITY_COMMON,  chain  },
    [PERK_TITAN]   = { "TITAN",   {"X2 MULT", "ON BIG",  "CLAIMS",  "(150+)"},  3, RARITY_SPECIAL, titan  },
    [PERK_SNIPER]  = { "SNIPER",  {"+6 MULT", "ON TINY", "CLAIMS",  "(<40)"},   5, RARITY_COMMON,  sniper },
    [PERK_HUNTER]  = { "HUNTER",  {"+3 MULT", "PER",     "SHARD",   "KILLED"},  5, RARITY_COMMON,  hunter },
    [PERK_SWIFT]   = { "SWIFT",   {"MOVE",    "FASTER",  "",        ""},        1, RARITY_COMMON,  0      },
    [PERK_AEGIS]   = { "AEGIS",   {"BLOCK",   "1 HIT",   "EACH",    "STAGE"},   3, RARITY_SPECIAL, 0      },
    [PERK_STASIS]  = { "STASIS",  {"CLAIMS",  "FREEZE",  "FOES",    "1.5 SEC"}, 3, RARITY_COMMON,  0      },
    [PERK_CHRONO]  = { "CHRONO",  {"FOES",    "MOVE",    "20%",     "SLOWER"},  3, RARITY_SPECIAL, 0      },
    [PERK_PHOENIX] = { "PHOENIX", {"+1 LIFE", "",        "",        ""},        9, RARITY_SPECIAL, 0      },
    [PERK_LUCKY]   = { "LUCKY",   {"+1",      "CAPSULE", "EACH",    "STAGE"},   2, RARITY_COMMON,  0      },
    [PERK_PRISM]   = { "PRISM",   {"+1 MULT", "PER",     "PERK",    "OWNED"},   5, RARITY_RARE,    prism  },
    [PERK_GLASS]   = { "GLASS",   {"X3 MULT", "BUT",     "-1 LIFE", ""},        1, RARITY_RARE,    glass  },
    [PERK_QUOTA]   = { "QUOTA",   {"GOAL",    "-5%",     "",        ""},        3, RARITY_SPECIAL, 0      },
    [PERK_JACKPOT] = { "JACKPOT", {"CAPSULE", "GIVES",   "+4 MULT", "(STAGE)"}, 5, RARITY_COMMON,  0      },
    [PERK_MIDAS]   = { "MIDAS",   {"STAGE",   "BONUS",   "X2",      ""},        3, RARITY_SPECIAL, 0      },
};
