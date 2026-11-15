/* NOLFIED - a territory-claiming arcade game for the SNES / Super Famicom.
 *
 * The main loop. Calypsi's startup code has already cleared WRAM (core.s,
 * __low_level_init) and initialised C data when main() runs. */
#include "game.h"
#include "hw.h"

uint16_t joy, joy_prev, joy_new;
uint16_t loops;
uint16_t busy_line;      /* scanline the last frame's work finished on (perf) */

#ifdef PROFILE
uint16_t prof_line[32];
uint8_t  prof_frame[32];
uint8_t  prof_bench;
#endif

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
        PROF(0);
        loops++;
        read_joy();
        PROF(1);
        juice_update();
        PROF(2);
        sfx_update();
        PROF(3);
        run_state();
        PROF(4);
        fsm_check();
        PROF(5);
        build_oam(state);
        PROF(6);
        busy_line = scanline();
        /* Publish the frame, then sleep until the NMI has uploaded it.
         * Waiting on frame_ready (not nmi_count) cannot miss an NMI that
         * lands right after the publish: spec/FrameSync.tla. */
        frame_ready = 1;
        while (frame_ready)
            ;
    }
}
