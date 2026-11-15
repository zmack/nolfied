/* Random numbers: 16-bit xorshift (legacy rand16). */
#include "game.h"

uint16_t rng;

uint16_t rand16(void)
{
    uint16_t x = rng;
    x ^= x << 7;
    x ^= x >> 9;
    x ^= x << 8;
    rng = x;
    return x;
}
