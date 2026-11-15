/* The perk deck: one row per perk, everything about it in one place.
 *
 *   SCORING(id, name, card text (4 lines, <= 7 chars), max, rarity, EFFECT)
 *   PASSIVE(id, name, card text (4 lines, <= 7 chars), max, rarity)
 *
 * EFFECT is a SCORING perk's contribution when a cut closes. It may use
 *   c  the claim (chips, chain, kills, perks_owned, stage_mult)
 *   n  how many stacks of this perk are owned
 *   m  the multiplier being built: m.plus (additive), m.times (multiplicative)
 * PASSIVE perks don't touch scoring; they act where their effect happens
 * (SWIFT in player movement, AEGIS in the hit handler, ...).
 *
 * This file is included several times with different SCORING()/PASSIVE()
 * definitions (the "X-macro" idiom): for the enum, the card table, the
 * scoring flags and the scoring switch in score.c.
 */
#define BIG_CLAIM   150
#define TINY_CLAIM   40

/*      id       name       card text                                    max  rarity   effect on the multiplier */
SCORING(GREED,   "GREED",   "+2 MULT", "EVERY",   "CLAIM",   "",          9, COMMON,  m.plus += 2 * n)
SCORING(CHAIN,   "CHAIN",   "CHAIN",   "LINKS",   "+1 MULT", "MORE",      5, COMMON,  m.plus += hw_mul8(c->chain, n))
SCORING(TITAN,   "TITAN",   "X2 MULT", "ON BIG",  "CLAIMS",  "(150+)",    3, SPECIAL, if (c->chips >= BIG_CLAIM) m.times *= 1 + n)
SCORING(SNIPER,  "SNIPER",  "+6 MULT", "ON TINY", "CLAIMS",  "(<40)",     5, COMMON,  if (c->chips < TINY_CLAIM) m.plus += 6 * n)
SCORING(HUNTER,  "HUNTER",  "+3 MULT", "PER",     "SHARD",   "KILLED",    5, COMMON,  m.plus += 3 * hw_mul8(n, c->kills))
PASSIVE(SWIFT,   "SWIFT",   "MOVE",    "FASTER",  "",        "",          1, COMMON)
PASSIVE(AEGIS,   "AEGIS",   "BLOCK",   "1 HIT",   "EACH",    "STAGE",     3, SPECIAL)
PASSIVE(STASIS,  "STASIS",  "CLAIMS",  "FREEZE",  "FOES",    "1.5 SEC",   3, COMMON)
PASSIVE(CHRONO,  "CHRONO",  "FOES",    "MOVE",    "20%",     "SLOWER",    3, SPECIAL)
PASSIVE(PHOENIX, "PHOENIX", "+1 LIFE", "",        "",        "",          9, SPECIAL)
PASSIVE(LUCKY,   "LUCKY",   "+1",      "CAPSULE", "EACH",    "STAGE",     2, COMMON)
SCORING(PRISM,   "PRISM",   "+1 MULT", "PER",     "PERK",    "OWNED",     5, RARE,    m.plus += hw_mul8(n, c->perks_owned))
SCORING(GLASS,   "GLASS",   "X3 MULT", "BUT",     "-1 LIFE", "",          1, RARE,    m.times *= 3)
PASSIVE(QUOTA,   "QUOTA",   "GOAL",    "-5%",     "",        "",          3, SPECIAL)
PASSIVE(JACKPOT, "JACKPOT", "CAPSULE", "GIVES",   "+4 MULT", "(STAGE)",   5, COMMON)
PASSIVE(MIDAS,   "MIDAS",   "STAGE",   "BONUS",   "X2",      "",          3, SPECIAL)
