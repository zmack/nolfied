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
typedef struct {
    uint16_t chips;         /* cells claimed by this cut */
    uint8_t  chain;         /* chain links before this claim */
    uint8_t  kills;         /* shards destroyed so far this stage */
    uint8_t  perks_owned;   /* total stacks of all perks */
    uint16_t stage_mult;    /* +mult banked this stage (JACKPOT capsules) */
} claim;

/* The multiplier being built: (plus) x (times). */
typedef struct {
    uint16_t plus;
    uint8_t  times;
} mult;

/* A hook receives the claim, how many stacks of this perk you own, and the
 * multiplier to add to. */
typedef void (*mult_hook)(const claim *c, uint8_t stacks, mult *m);

typedef struct {
    const char *name;
    const char *text[4];    /* card text, 4 lines of up to 7 chars */
    uint8_t     max_stacks;
    rarity      rarity;
    mult_hook   on_claim;   /* NULL: the perk does not touch scoring */
} perk_def;

extern const perk_def perk_table[PERK_COUNT];

#endif
