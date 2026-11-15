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
volatile uint8_t bench_done;

__attribute__((interrupt(0xffea))) void nmi(void)
{
    (void)REG(0x4210);           /* acknowledge */
    frames++;
}

static void stamp(uint16_t *h, uint16_t *v, uint8_t *f)
{
    (void)REG(0x2137);           /* latch H/V */
    (void)REG(0x213F);           /* reset the lo/hi read toggle */
    uint8_t hl = REG(0x213C), hh = REG(0x213C);
    uint8_t vl = REG(0x213D), vh = REG(0x213D);
    *h = hl | ((hh & 1) << 8);
    *v = vl | ((vh & 1) << 8);
    *f = frames;
}

int main(void)
{
    REG(0x2100) = 0x80;          /* forced blank */
    REG(0x4200) = 0x80;          /* NMI on: counts frames */

    for (uint8_t i = 0; i < N_VECTORS; i++) {
        const unsigned char *r = &vectors[i * 24];
        claim c = {
            .chips = r[0] | (r[1] << 8), .chain = r[2], .kills = r[3],
            .stage_mult = r[4] | (r[5] << 8), .perks_owned = r[6],
        };
        result *out = &results[i];
        stamp(&out->h0, &out->v0, &out->f0);
        out->points = claim_points(&c, &r[8], &out->mult);
        stamp(&out->h1, &out->v1, &out->f1);
    }
    bench_done = 1;
    for (;;) { }
}
