/* Screen shake and colour flashes. */
#include "game.h"

uint8_t shake_t;
int8_t  sh_x, sh_y;

#define SHAKE_BIG_ABOVE 10      /* shake_t >= this: the big offsets */

static const int8_t shake_big[4]   = { -2, -1, 1, 2 };
static const int8_t shake_small[4] = { -1,  0, 0, 1 };

void flash(uint8_t r, uint8_t g, uint8_t b)
{
    fl_r = r;
    fl_g = g;
    fl_b = b;
}

void juice_update(void)
{
    if (shake_t) {
        shake_t--;
        const int8_t *tab = shake_t >= SHAKE_BIG_ABOVE ? shake_big : shake_small;
        sh_x = tab[rand16() & 3];
        sh_y = tab[rand16() & 3];
    } else {
        sh_x = 0;
        sh_y = 0;
    }

    /* BG1 scrolls by the offset; BG2's vertical scroll has the usual -1 */
    scr_h = (uint16_t)(int16_t)sh_x & 0x3FF;
    scr_v = (uint16_t)(0x3FF + (int16_t)sh_y) & 0x3FF;

    if (fl_r) fl_r--;
    if (fl_g) fl_g--;
    if (fl_b) fl_b--;
}
