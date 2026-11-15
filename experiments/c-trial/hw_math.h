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

/* x << 8 for 32-bit values. A plain `<< 8` compiles to an 8-step shift loop;
 * moving bytes is what the hardware is good at. */
typedef union { uint32_t u; uint8_t b[4]; } bytes32;

static inline uint32_t shl8_32(uint32_t x)
{
    bytes32 in = { x }, out;
    out.b[0] = 0;
    out.b[1] = in.b[0];
    out.b[2] = in.b[1];
    out.b[3] = in.b[2];
    return out.u;
}

/* 16 x 8 -> 24 bits (returned as 32) */
static inline uint32_t mul16x8(uint16_t a, uint8_t b)
{
    uint32_t lo = hw_mul8(a, b);
    uint32_t hi = hw_mul8(a >> 8, b);
    return lo + shl8_32(hi);
}

/* 16 x 16 -> 32 bits, from four 8x8 products */
static inline uint32_t mul16x16(uint16_t a, uint16_t b)
{
    uint32_t ll = hw_mul8(a, b);
    uint32_t lh = hw_mul8(a, b >> 8);
    uint32_t hl = hw_mul8(a >> 8, b);
    uint32_t hh = hw_mul8(a >> 8, b >> 8);
    return ll + shl8_32(lh + hl) + (hh << 16);
}

#endif
