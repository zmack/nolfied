#ifndef SCORE_H
#define SCORE_H

#include <stdint.h>
#include "perks.h"

#define MULT_CAP 999

/* Multiplier for a claim, given how many stacks of each perk are owned. */
uint16_t claim_mult(const claim *c, const uint8_t stacks[PERK_COUNT]);

/* Points (in units of 10) a claim is worth: chips x mult. */
uint32_t claim_points(const claim *c, const uint8_t stacks[PERK_COUNT], uint16_t *mult_out);

#endif
