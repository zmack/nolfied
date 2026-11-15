/* NOLFIED - a territory-claiming arcade game for the SNES / Super Famicom.
 *
 * The main loop. Calypsi's startup code has already cleared WRAM (core.s,
 * __low_level_init) and initialised C data when main() runs. */
#include "game.h"
#include "hw.h"

uint16_t joy, joy_prev, joy_new;
uint16_t loops;
uint16_t busy_line;      /* scanline the last frame's work finished on (perf) */

/* current scanline from the PPU's latched V counter */
static uint16_t scanline(void)
{
    (void)REG8(0x2137);             /* latch H/V */
    (void)REG8(0x213F);             /* reset the lo/hi read toggle */
    uint16_t lo = REG8(0x213D);
    uint16_t hi = REG8(0x213D) & 1;
    return lo | (hi << 8);
}

static void read_joy(void)
{
    while (HVBJOY & 1)              /* auto-read still in progress */
        ;
    joy_prev = joy;
    joy = JOY1;
    joy_new = joy & ~joy_prev;
}

int main(void)
{
    core_boot_ppu();
    spc_init();
    load_static();
    oam_init();
    rng = 0xACE1;
    state = ST_BOOT;
    goto_state(ST_TITLE);

    for (;;) {
        loops++;
        read_joy();
        juice_update();
        sfx_update();
        run_state();
        fsm_check();
        build_oam(state);
        busy_line = scanline();
        /* Publish the frame, then sleep until the NMI has uploaded it.
         * Waiting on frame_ready (not nmi_count) cannot miss an NMI that
         * lands right after the publish: spec/FrameSync.tla. */
        frame_ready = 1;
        while (frame_ready)
            ;
    }
}
