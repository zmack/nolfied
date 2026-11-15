/* SNES hardware multiplier, used explicitly.
 *
 * The CPU has an unsigned 8x8 multiplier: write $4202 and $4203, wait 8 CPU
 * cycles, read the 16-bit product at $4216. We drive it by hand because
 * Calypsi's own --target=SNES use of it is miscompiled in 5.18 (README.md).
 *
 * Only the main loop may use these: the NMI handler never touches the
 * multiplier (see spec/FrameSync.tla's assumptions).
 */
#ifndef HW_MATH_H
#define HW_MATH_H

#include <stdint.h>
#include <calypsi/intrinsics65816.h>

#define HW_WRMPYA (*(volatile uint8_t *)0x4202)
#define HW_WRMPYB (*(volatile uint8_t *)0x4203)
#define HW_RDMPY  (*(volatile uint16_t *)0x4216)

/* A macro, not a function: Calypsi 5.18 will not inline a function that
 * touches volatile registers, and a call costs far more than the multiply. */
#define hw_mul8(a, b) (HW_WRMPYA = (uint8_t)(a),                         \
                       HW_WRMPYB = (uint8_t)(b),  /* starts the multiply */ \
                       __no_operation(), __no_operation(), /* 8 cycles */ \
                       __no_operation(), __no_operation(),                \
                       HW_RDMPY)

/* Each hw_mul8() must be its own statement: the operands of `+` are
 * unsequenced in C, so two multiplies in one expression may interleave their
 * register writes. */

/* Wider products are assembled in 16-bit halves: on the 65816 a 16-bit
 * `x << 8` is two instructions (xba; and), while a 32-bit shift is a loop. */

/* 16 x 8 -> 24 bits */
static inline uint32_t mul16x8(uint16_t a, uint8_t b)
{
    uint16_t lo = hw_mul8(a, b);
    uint16_t hi = hw_mul8(a >> 8, b);       /* weight 256 */
    uint16_t sum = lo + (hi << 8);
    uint16_t top = (hi >> 8) + (sum < lo);  /* carry out of the low half */
    return ((uint32_t)top << 16) | sum;
}

/* 16 x 16 -> 32 bits, from four 8x8 products */
static inline uint32_t mul16x16(uint16_t a, uint16_t b)
{
    uint16_t ll = hw_mul8(a, b);
    uint16_t lh = hw_mul8(a, b >> 8);       /* weight 256 */
    uint16_t hl = hw_mul8(a >> 8, b);       /* weight 256 */
    uint16_t hh = hw_mul8(a >> 8, b >> 8);  /* weight 65536 */

    uint16_t lo = ll + (lh << 8);
    uint16_t hi = hh + (lh >> 8) + (lo < ll);
    uint16_t lo2 = lo + (hl << 8);
    hi += (hl >> 8) + (lo2 < lo);
    return ((uint32_t)hi << 16) | lo2;
}

#endif
