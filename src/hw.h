/* SNES hardware registers used from C, and the hardware multiplier. */
#ifndef HW_H
#define HW_H

#include <stdint.h>
#include <calypsi/intrinsics65816.h>

#define REG8(a)  (*(volatile uint8_t *)(a))
#define REG16(a) (*(volatile uint16_t *)(a))

#define INIDISP   REG8(0x2100)
#define TM        REG8(0x212C)
#define NMITIMEN  REG8(0x4200)
#define RDNMI     REG8(0x4210)
#define HVBJOY    REG8(0x4212)
#define JOY1      REG16(0x4218)
#define WRDIVL    REG16(0x4204)
#define WRDIVB    REG8(0x4206)
#define RDDIV     REG16(0x4214)
#define RDMPY     REG16(0x4216)   /* product, or division remainder */

/* joypad bits (JOY1, as read) */
#define BTN_B      0x8000
#define BTN_Y      0x4000
#define BTN_SELECT 0x2000
#define BTN_START  0x1000
#define BTN_UP     0x0800
#define BTN_DOWN   0x0400
#define BTN_LEFT   0x0200
#define BTN_RIGHT  0x0100
#define BTN_A      0x0080
#define BTN_X      0x0040
#define BTN_CUT    (BTN_B | BTN_Y | BTN_A | BTN_X)

/* ---- the CPU's 8x8 hardware multiplier --------------------------------
 * Write $4202 and $4203, wait 8 cycles, read the product at $4216.
 * Driven by hand: Calypsi 5.18's own --target=SNES use of it is miscompiled
 * (experiments/c-trial/README.md). Only the main loop may use it: the NMI
 * never touches the multiplier or the divider (spec/FrameSync.tla).
 *
 * hw_mul8 is a macro because Calypsi will not inline a function that touches
 * volatile registers. Each use must be its own statement: the operands of
 * `+` are unsequenced, and two multiplies in one expression interleave. */
#define hw_mul8(a, b) (REG8(0x4202) = (uint8_t)(a),                     \
                       REG8(0x4203) = (uint8_t)(b),                     \
                       __no_operation(), __no_operation(),              \
                       __no_operation(), __no_operation(),              \
                       RDMPY)

/* 16 x 8 -> 24 bits, assembled in 16-bit halves (a 32-bit shift is a loop) */
static inline uint32_t mul16x8(uint16_t a, uint8_t b)
{
    uint16_t lo = hw_mul8(a, b);
    uint16_t hi = hw_mul8(a >> 8, b);
    uint16_t sum = lo + (hi << 8);
    uint16_t top = (hi >> 8) + (sum < lo);
    return ((uint32_t)top << 16) | sum;
}

/* 16 x 16 -> 32 bits from four 8x8 products */
static inline uint32_t mul16x16(uint16_t a, uint16_t b)
{
    uint16_t ll = hw_mul8(a, b);
    uint16_t lh = hw_mul8(a, b >> 8);
    uint16_t hl = hw_mul8(a >> 8, b);
    uint16_t hh = hw_mul8(a >> 8, b >> 8);
    uint16_t lo = ll + (lh << 8);
    uint16_t hi = hh + (lh >> 8) + (lo < ll);
    uint16_t lo2 = lo + (hl << 8);
    hi += (hl >> 8) + (lo2 < lo);
    return ((uint32_t)hi << 16) | lo2;
}

/* current scanline, from the PPU's latched V counter */
static inline uint16_t scanline(void)
{
    (void)REG8(0x2137);             /* latch H/V */
    (void)REG8(0x213F);             /* reset the lo/hi read toggle */
    uint16_t lo = REG8(0x213D);
    uint16_t hi = REG8(0x213D) & 1;
    return lo | (hi << 8);
}

/* profiling build only (make profile): PROF(n) stamps the time at point n */
#ifdef PROFILE
extern volatile uint8_t nmi_count;
extern uint16_t prof_line[32];
extern uint8_t  prof_frame[32];
extern uint8_t  prof_bench;
#define PROF(n) (prof_line[n] = scanline(), prof_frame[n] = nmi_count)
#else
#define PROF(n) ((void)0)
#endif

/* 16 / 8 hardware divider: quotient, remainder in RDMPY. 16 cycles. */
static inline uint16_t hw_div8(uint16_t a, uint8_t b)
{
    WRDIVL = a;
    WRDIVB = b;
    __no_operation(); __no_operation(); __no_operation(); __no_operation();
    __no_operation(); __no_operation(); __no_operation(); __no_operation();
    return RDDIV;
}

#endif
