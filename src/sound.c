/* Sound effects and jingles: a three-channel note sequencer driving S-DSP
 * voices 0..2 (voice = channel). The music is music.c, on voices 3..7. */
#include "game.h"

#define NOTE(d, p, v) { (d), (p), (v) }
#define END           { 0, 0, 0 }

const note sfx_cut[] = {
    NOTE(2, 1606, 0x30), NOTE(3, 2144, 0x24), END };
const note sfx_claim[] = {
    NOTE(3, 1072, 0x40), NOTE(3, 1350, 0x40), NOTE(3, 1606, 0x40),
    NOTE(4, 2144, 0x40), NOTE(4, 2144, 0x20), NOTE(4, 2144, 0x10), END };
const note sfx_item[] = {
    NOTE(3, 2701, 0x40), NOTE(3, 3211, 0x40), NOTE(3, 4287, 0x40),
    NOTE(8, 4287, 0x20), END };
const note sfx_death[] = {
    NOTE(4, 28, 0x70), NOTE(6, 24, 0x60), NOTE(8, 20, 0x48),
    NOTE(10, 16, 0x30), NOTE(12, 12, 0x18), NOTE(12, 8, 0x0C), END };
const note sfx_kill[] = {
    NOTE(3, 30, 0x60), NOTE(4, 26, 0x40), NOTE(6, 22, 0x20), END };
const note sfx_tick[] = {
    NOTE(2, 3211, 0x28), END };

const note jingle_start[] = {
    NOTE(8, 2142, 0x50), NOTE(8, 2699, 0x50), NOTE(8, 3211, 0x50),
    NOTE(16, 4288, 0x50), NOTE(12, 4288, 0x20), END };
const note jingle_clear[] = {
    NOTE(6, 2142, 0x50), NOTE(6, 2699, 0x50), NOTE(6, 3211, 0x50),
    NOTE(6, 4288, 0x50), NOTE(6, 5402, 0x50), NOTE(6, 6423, 0x50),
    NOTE(24, 8573, 0x50), NOTE(16, 8573, 0x20), END };
const note jingle_over[] = {
    NOTE(14, 1606, 0x50), NOTE(14, 1351, 0x50), NOTE(14, 1072, 0x50),
    NOTE(30, 803, 0x50), NOTE(20, 803, 0x20), END };
const note jingle_draft[] = {
    NOTE(5, 3211, 0x40), NOTE(5, 4288, 0x40), NOTE(10, 6423, 0x40),
    NOTE(10, 6423, 0x18), END };

/* DSP registers */
#define DSP_KON   0x4C
#define DSP_FLG   0x6C
#define VOLL      0
#define VOLR      1
#define PITCHL    2
#define PITCHH    3
/* FLG: bits 0-4 are the noise clock; bit 5 clear keeps the echo running (music.c) */

static const note *ch_ptr[CH_COUNT];     /* next step, or 0: channel idle */
static uint8_t     ch_timer[CH_COUNT];
static uint8_t     ch_new[CH_COUNT];     /* first step still to come: key on */

/* DSP register := value. A macro: it runs up to 20 times a frame, and Calypsi
 * does not inline. */
#define dsp(reg, val) apu_write(((uint16_t)(reg) << 8) | (uint8_t)(val))

void sfx(uint8_t channel, const note *n)
{
    ch_ptr[channel] = n;
    ch_timer[channel] = 1;
    ch_new[channel] = 1;
}

static void voice_volume(small_t base, small_t vol)
{
    dsp(base + VOLL, vol);
    dsp(base + VOLR, vol);
}

static void play_step(small_t ch, const note *n)
{
    small_t base = ch << 4;
    ch_timer[ch] = n->dur;
    if (ch == CH_NOISE) {
        dsp(DSP_FLG, (uint8_t)n->pitch & 0x1F);       /* pitch is the noise rate */
    } else {
        dsp(base + PITCHL, n->pitch);
        dsp(base + PITCHH, n->pitch >> 8);
    }
    voice_volume(base, n->vol);
    if (ch_new[ch]) {
        ch_new[ch] = 0;
        dsp(DSP_KON, 1 << ch);
    }
    ch_ptr[ch] = n + 1;
}

void sfx_update(void)
{
    for (small_t ch = 0; ch < CH_COUNT; ch++) {
        const note *n = ch_ptr[ch];
        if (!n || --ch_timer[ch])
            continue;
        small_t dur = n->dur;
        if (dur == 0) {                       /* end: silence the voice */
            ch_ptr[ch] = 0;
            voice_volume(ch << 4, 0);
        } else {
            play_step(ch, n);
        }
    }
    music_update();
}
