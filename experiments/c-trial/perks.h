/* Perks: the roguelite layer of NOLFIED.
 *
 * A perk is data plus a few optional hooks. Game code never asks "which perk
 * is this?" - it asks every owned perk to contribute, so adding a perk means
 * adding one table entry and (at most) one small function.
 */
#ifndef PERKS_H
#define PERKS_H

#include <stdint.h>

typedef enum {
    PERK_GREED, PERK_CHAIN, PERK_TITAN, PERK_SNIPER,
    PERK_HUNTER, PERK_SWIFT, PERK_AEGIS, PERK_STASIS,
    PERK_CHRONO, PERK_PHOENIX, PERK_LUCKY, PERK_PRISM,
    PERK_GLASS, PERK_QUOTA, PERK_JACKPOT, PERK_MIDAS,
    PERK_COUNT
} perk_id;

typedef enum { RARITY_COMMON, RARITY_SPECIAL, RARITY_RARE } rarity;

/* Everything a perk may look at when a cut closes. */
/* Values are 8-bit quantities, but uint_fast8_t (16 bits on the 65816) is
 * what the CPU handles without mode switches. Storage elsewhere stays uint8_t. */
typedef struct {
    uint16_t      chips;        /* cells claimed by this cut */
    uint_fast8_t  chain;        /* chain links before this claim */
    uint_fast8_t  kills;        /* shards destroyed so far this stage */
    uint_fast8_t  perks_owned;  /* total stacks of all perks */
    uint16_t      stage_mult;   /* +mult banked this stage (JACKPOT capsules) */
} claim;

/* The multiplier being built: (plus) x (times). */
typedef struct {
    uint16_t     plus;
    uint_fast8_t times;
} mult;

/* A hook receives the claim, how many stacks of this perk you own, and the
 * multiplier to add to. */
typedef void (*mult_hook)(const claim *c, uint_fast8_t stacks, mult *m);

/* Card data: only needed on the draft screen. */
typedef struct {
    const char *name;
    const char *text[4];    /* card text, 4 lines of up to 7 chars */
    uint8_t     max_stacks;
    rarity      rarity;
} perk_card;

extern const perk_card perk_cards[PERK_COUNT];

/* Scoring hook per perk (NULL: the perk does not touch the multiplier). */
extern const mult_hook perk_on_claim[PERK_COUNT];

/* What the player owns. `scorers` lists only owned perks that have a claim
 * hook, so scoring a claim never looks at the rest of the deck. */
typedef struct {
    mult_hook    hook;
    uint_fast8_t stacks;
} scorer;

typedef struct {
    uint8_t  stacks[PERK_COUNT];
    uint8_t  total;                 /* stacks of all perks together */
    uint8_t  n_scorers;
    scorer   scorers[PERK_COUNT];
} loadout;

void loadout_clear(loadout *l);
void loadout_take(loadout *l, perk_id p);     /* one more stack of p */

#endif
