/* Perks: the roguelite layer. The deck itself is perk_defs.h. */
#ifndef PERKS_H
#define PERKS_H

#include <stdint.h>

typedef enum {
#define SCORING(id, name, t1, t2, t3, t4, max, rarity, effect) PERK_##id,
#define PASSIVE(id, name, t1, t2, t3, t4, max, rarity)         PERK_##id,
#include "perk_defs.h"
#undef SCORING
#undef PASSIVE
    PERK_COUNT
} perk_id;

typedef enum { RARITY_COMMON, RARITY_SPECIAL, RARITY_RARE } rarity;

/* Everything a perk may look at when a cut closes. Values are 8-bit
 * quantities held in uint_fast8_t (16 bits on the 65816: no mode switches). */
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

/* Card data, for the draft screen. */
typedef struct {
    const char *name;
    const char *text[4];
    uint8_t     max_stacks;
    rarity      rarity;
} perk_card;

extern const perk_card perk_cards[PERK_COUNT];
extern const uint8_t   rarity_weight[3];         /* draft odds: 4 / 2 / 1 */

/* What the player owns. `scorers` lists only owned SCORING perks, so scoring
 * a claim never looks at the rest of the deck.
 * Layout note: tools/ read `stacks` at offset 0 and `total` at offset 16. */
typedef struct {
    uint_fast8_t id;
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
void loadout_rebuild(loadout *l);             /* scorers from stacks[] */

uint16_t claim_mult(const claim *c, const loadout *l);
uint32_t claim_points(const claim *c, const loadout *l, uint16_t *mult_out);
#define MULT_CAP 999

#endif
