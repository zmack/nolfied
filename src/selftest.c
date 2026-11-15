/* Self-tests run inside the PROFILE build (tools/test_selftest.py).
 * Empty in the shipped ROM. */
#include "game.h"
#include "hw.h"

#ifdef PROFILE
uint16_t selftest_runs, selftest_errs;
uint8_t  selftest_bad[6];          /* first failing box: bx0, bx1, by0, by1, want, got */

/* The specification of box_scan(): the OR of (1 << state) over every cell
 * under the box. Pixel coordinates outside the field are clamped (a low edge
 * to 0, a high edge to the last pixel) and the box is always at least one
 * cell; state values 5..7 contribute nothing. */
static uint16_t box_scan_model(void)
{
    uint16_t x0 = (bx0 < 240 ? bx0 : 0) >> 2, x1 = (bx1 < 240 ? bx1 : 239) >> 2;
    uint16_t y0 = (by0 < 192 ? by0 : 0) >> 2, y1 = (by1 < 192 ? by1 : 191) >> 2;
    if (x1 < x0)
        x1 = x0;
    if (y1 < y0)
        y1 = y0;
    uint16_t flags = 0;
    for (uint16_t y = y0; y <= y1; y++)
        for (uint16_t x = x0; x <= x1; x++) {
            uint16_t v = grid[y * 64 + x] & 7;
            if (v < 5)
                flags |= 1 << v;
        }
    return flags;
}

/* n random boxes, the first half anywhere (clamping), the rest small boxes
 * inside the field like the enemies' */
void selftest_box_scan(uint16_t n)
{
    for (uint16_t i = 0; i < n; i++) {
        uint16_t r = rand16(), q = rand16();
        if (i & 1) {
            bx0 = (uint8_t)r; bx1 = (uint8_t)(r >> 8);
            by0 = (uint8_t)q; by1 = (uint8_t)(q >> 8);
        } else {
            uint16_t x = (r & 0xFF) % 240, y = (q & 0xFF) % 192, h = (r >> 8) & 15;
            bx0 = (uint8_t)(x - h); bx1 = (uint8_t)(x + h);
            by0 = (uint8_t)(y - h); by1 = (uint8_t)(y + h);
        }
        uint8_t a = bx0, b = bx1, c = by0, d = by1;
        uint16_t want = box_scan_model();
        bx0 = a; bx1 = b; by0 = c; by1 = d;
        uint16_t got = box_scan();
        selftest_runs++;
        if (got != want) {
            if (!selftest_errs) {
                selftest_bad[0] = a; selftest_bad[1] = b;
                selftest_bad[2] = c; selftest_bad[3] = d;
                selftest_bad[4] = (uint8_t)want; selftest_bad[5] = (uint8_t)got;
            }
            selftest_errs++;
        }
    }
}

/* put_num / put_score / put_dec2 against plain % 10 (slow software division
 * is fine here), drawn on BG3 row 30, which is below the visible screen. */
static uint16_t check_digits(uint16_t at, uint32_t v, small_t n, small_t attr)
{
    uint16_t errs = 0;
    for (small_t i = n; i--; ) {
        uint16_t want = ((uint16_t)attr << 8) | (16 + (uint16_t)(v % 10));
        if (bg3map[at + i] != want)
            errs++;
        v /= 10;
    }
    return errs;
}

static small_t ndigits(uint32_t v)
{
    small_t n = 1;
    while (v >= 10) {
        v /= 10;
        n++;
    }
    return n;
}

void selftest_numbers(uint16_t n)
{
    const uint16_t at = MAP(30, 0);
    for (uint16_t i = 0; i < n; i++) {
        uint32_t v = ((uint32_t)rand16() << 16) | rand16();
        v >>= rand16() & 31;                        /* all magnitudes */
        uint16_t errs = 0;

        uint16_t end = put_num(at, v, ATTR_Y);
        errs += (end != at + ndigits(v)) + check_digits(at, v, ndigits(v), ATTR_Y);

        uint32_t units = v % 10000000;
        end = put_score(at, units, ATTR_G);
        errs += (end != at + 8) + check_digits(at, units * 10, 8, ATTR_G);

        uint8_t d = (uint8_t)(v % 100);
        end = put_dec2(at, d, ATTR_W);
        errs += (end != at + 2) + check_digits(at, d, 2, ATTR_W);

        selftest_runs++;
        if (errs)
            selftest_errs++;
    }
    clear_row(30);
}
#endif
