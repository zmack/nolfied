/* Benchmark ROM: score every vector with the C module, time each call with
 * the PPU's H/V counters, and leave the results in RAM for the test harness. */
#include <stdint.h>
#include "score.h"
#include "vectors.h"

#define REG(a) (*(volatile uint8_t *)(a))

typedef struct {
    uint16_t mult;
    uint32_t points;
    uint16_t h0, v0;  uint8_t f0;
    uint16_t h1, v1;  uint8_t f1;
} result;

volatile uint8_t frames;
result results[N_VECTORS];
result calib;                    /* empty window: harness overhead */
volatile uint8_t bench_done;

__attribute__((interrupt(0xffea))) void nmi(void)
{
    (void)REG(0x4210);           /* acknowledge */
    frames++;
}

/* inlined like the assembly STAMP macro, so both sides pay the same */
#define STAMP(h, v, f) do {                                     \
        (f) = frames;              /* re-sampled below if */    \
        (void)REG(0x2137);         /* latch H/V */              \
        (void)REG(0x213F);         /* reset the lo/hi toggle */ \
        uint8_t hl_ = REG(0x213C), hh_ = REG(0x213C);           \
        uint8_t vl_ = REG(0x213D), vh_ = REG(0x213D);           \
        (h) = hl_ | ((hh_ & 1) << 8);                           \
        (v) = vl_ | ((vh_ & 1) << 8);                           \
    } while ((f) != frames)        /* vblank started meanwhile */

int main(void)
{
    REG(0x2100) = 0x80;          /* forced blank */
    REG(0x4200) = 0x80;          /* NMI on: counts frames */

    STAMP(calib.h0, calib.v0, calib.f0);
    STAMP(calib.h1, calib.v1, calib.f1);

    for (uint8_t i = 0; i < N_VECTORS; i++) {
        const unsigned char *r = &vectors[i * 24];
        claim c = {
            .chips = r[0] | (r[1] << 8), .chain = r[2], .kills = r[3],
            .stage_mult = r[4] | (r[5] << 8), .perks_owned = r[6],
        };
        static loadout lo;
        loadout_clear(&lo);                       /* not timed: a draft pick */
        for (unsigned p = 0; p < PERK_COUNT; p++)
            for (uint8_t k = r[8 + p]; k; k--)
                loadout_take(&lo, (perk_id)p);
        result *out = &results[i];
        STAMP(out->h0, out->v0, out->f0);
        out->points = claim_points(&c, &lo, &out->mult);
        STAMP(out->h1, out->v1, out->f1);
    }
    bench_done = 1;
    for (;;) { }
}
