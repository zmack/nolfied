/* In-game music: a five-track synthpop sequencer on S-DSP voices 3..7.
 *
 * Dark-synthpop in A minor, about 129 BPM (a 16th note is 7 frames):
 * a plucked saw bass in octaves, saw-chord stabs, a drum machine (kick, a
 * big echoed snare, hats and a metal clank), and a pulse lead that comes in
 * for the second half. 16 bars, then it loops (about 30 seconds).
 *
 * The score is written like a tracker: one row of 16 steps per bar and
 * track; __ holds the note, xx releases it. Each bar names a pattern, a
 * transposition and an instrument, so one bass line serves every chord.
 *
 * Voices 0..2 belong to the sound effects (sound.c). The lead, stabs and
 * percussion run through the DSP echo (an 8th-note delay, low-passed); its
 * buffer is SPC RAM $7000-$E7FF, above the samples (tools/gen_samples.py).
 */
#include "game.h"
#include "spc_samples.h"

#define STEP_FRAMES 7
#define STEPS       16
#define SONG_BARS   16

/* ---- DSP registers ------------------------------------------------------ */
#define V_VOLL  0x00                /* per voice: register | (voice << 4) */
#define V_VOLR  0x01
#define V_PITCHL 0x02
#define V_PITCHH 0x03
#define V_SRCN  0x04
#define V_ADSR1 0x05
#define V_ADSR2 0x06
#define DSP_KON  0x4C
#define DSP_KOFF 0x5C
#define DSP_FLG  0x6C
#define DSP_EON  0x4D
#define DSP_EFB  0x0D
#define DSP_EVOLL 0x2C
#define DSP_EVOLR 0x3C
#define DSP_ESA  0x6D
#define DSP_EDL  0x7D
#define DSP_FIR(i) (0x0F | ((i) << 4))

#define dsp(reg, val) apu_write(((uint16_t)(reg) << 8) | (uint8_t)(val))

/* ---- instruments ------------------------------------------------------------
 * ADSR1 = 0x80 | decay << 4 | attack, ADSR2 = sustain level << 5 | sustain rate */
typedef struct {
    uint8_t  sample, adsr1, adsr2, vol_l, vol_r;
    uint8_t  pitch_shift;           /* chords: 32 samples per root cycle -> >> 1 */
    uint16_t fixed_pitch;           /* drums: play at this pitch, whatever the note */
} instrument;

enum { I_BASS, I_STAB_MIN, I_STAB_MAJ, I_LEAD, I_KICK, I_SNARE, I_HAT, I_CLANK };

static const instrument inst[] = {
    [I_BASS]     = { SAMPLE_SAW,       0xEF, 0x50, 0x46, 0x46, 0, 0 },   /* pluck */
    [I_STAB_MIN] = { SAMPLE_CHORD_MIN, 0xCF, 0x6E, 0x3C, 0x48, 1, 0 },   /* stab, decays */
    [I_STAB_MAJ] = { SAMPLE_CHORD_MAJ, 0xCF, 0x6E, 0x3C, 0x48, 1, 0 },
    [I_LEAD]     = { SAMPLE_PULSE,     0xBD, 0xA6, 0x30, 0x22, 0, 0 },
    [I_KICK]     = { SAMPLE_KICK,      0x8F, 0xE0, 0x5C, 0x5C, 0, 0x0800 },
    [I_SNARE]    = { SAMPLE_SNARE,     0x8F, 0xE0, 0x58, 0x58, 0, 0x0800 },
    [I_HAT]      = { SAMPLE_HAT,       0x8F, 0xE0, 0x18, 0x2A, 0, 0x1000 },
    [I_CLANK]    = { SAMPLE_CLANK,     0x8F, 0xE0, 0x3C, 0x22, 0, 0x0800 },
};

/* drum symbols in the percussion rows (after __ and xx) */
enum { KK = 2, SN, HH, CL };
#define DRUM_INST(v) (I_KICK + (v) - KK)

/* ---- the score ----------------------------------------------------------- */

/* the patterns, one bar of 16 steps each */
enum {
    P_BASS_DRIVE, P_BASS_TURN, P_STAB_332, P_STAB_PUSH,
    P_KICK_FOUR, P_KICK_SKIP, P_PERC_BEAT, P_PERC_METAL, P_PERC_FILL,
    P_SILENT, P_LEAD_1, P_LEAD_2, P_LEAD_3, P_LEAD_4, P_LEAD_5, P_LEAD_6, P_LEAD_7, P_LEAD_8,
    PATTERNS
};

static const uint8_t pattern[PATTERNS][STEPS] = {
    /* bass: octave pulses, written on A and transposed */
    [P_BASS_DRIVE] = {
        A2, xx, A2, A3,  A2, xx, A2, A3,  A2, xx, A2, A3,  A2, A3, A2, A3 },
    [P_BASS_TURN] = {
        A2, xx, A2, A3,  A2, xx, A2, A3,  A2, A3, xx, A3,  G3, xx, E3, xx },

    /* chord stabs, 3-3-2 against the beat, written on A3 */
    [P_STAB_332] = {
        A3, __, __, __,  __, __, A3, __,  __, __, A3, __,  __, __, __, __ },
    [P_STAB_PUSH] = {
        A3, __, __, __,  __, __, A3, __,  __, __, A3, __,  __, A3, __, A3 },

    /* drums */
    [P_KICK_FOUR] = {
        KK, __, __, __,  KK, __, __, __,  KK, __, __, __,  KK, __, __, __ },
    [P_KICK_SKIP] = {
        KK, __, __, __,  KK, __, __, KK,  KK, __, KK, __,  KK, __, __, __ },
    [P_PERC_BEAT] = {
        __, __, HH, __,  SN, __, HH, __,  __, __, HH, __,  SN, __, HH, __ },
    [P_PERC_METAL] = {
        __, __, HH, __,  SN, __, HH, CL,  __, __, HH, __,  SN, __, HH, HH },
    [P_PERC_FILL] = {
        __, __, HH, __,  SN, __, HH, CL,  __, __, HH, SN,  SN, CL, SN, SN },

    /* the lead: a falling, melancholy line over the second eight bars */
    [P_SILENT] = {
        xx, __, __, __,  __, __, __, __,  __, __, __, __,  __, __, __, __ },
    [P_LEAD_1] = {
        E5, __, __, __,  D5, __, C5, __,  B4, __, C5, __,  __, __, A4, __ },
    [P_LEAD_2] = {
        xx, __, C5, __,  D5, __, E5, __,  xx, __, G5, __,  E5, __, __, __ },
    [P_LEAD_3] = {
        F5, __, __, __,  E5, __, C5, __,  xx, __, A4, __,  C5, __, __, __ },
    [P_LEAD_4] = {
        D5, __, __, __,  C5, __, A4, __,  __, __, __, __,  xx, __, __, __ },
    [P_LEAD_5] = {
        D5, __, __, __,  F5, __, A5, __,  G5, __, F5, __,  E5, __, D5, __ },
    [P_LEAD_6] = {
        F5, __, __, __,  E5, __, D5, __,  xx, __, A4, __,  __, __, xx, __ },
    [P_LEAD_7] = {
        Gs4, __, B4, __, E5, __, Gs5, __, xx, __, F5, __,  E5, __, D5, __ },
    [P_LEAD_8] = {
        E5, __, __, __,  __, __, __, __,  B4, __, __, __,  Gs4, __, xx, __ },
};

/* A bar of one track names a pattern by number, not by pointer: Calypsi 5.18
 * miscompiles song[t][b].steps[i] when steps is a pointer member (it indexes
 * the struct instead of the pointed-to row; docs/PORTING.md). */
typedef struct {
    uint8_t pattern;
    int8_t  transpose;              /* semitones */
    uint8_t inst;                   /* pitched tracks; drums name their own */
} bar;

/* the progression, two bars each: Am  F  Dm  E (i VI iv V) */
#define AM   0, I_STAB_MIN
#define FM  -4, I_STAB_MAJ
#define DM  -7, I_STAB_MIN
#define EM  -5, I_STAB_MAJ

enum { T_KICK, T_PERC, T_BASS, T_STAB, T_LEAD, TRACKS };
static const uint8_t track_voice[TRACKS] = { 3, 7, 4, 6, 5 };
#define MUSIC_VOICES 0xF8           /* voices 3..7 */
#define ECHO_VOICES  0xE0           /* lead (5), stabs (6), percussion (7) */

static const bar song[TRACKS][SONG_BARS] = {
    [T_KICK] = {
        { P_KICK_FOUR }, { P_KICK_FOUR }, { P_KICK_FOUR }, { P_KICK_SKIP },
        { P_KICK_FOUR }, { P_KICK_FOUR }, { P_KICK_FOUR }, { P_KICK_SKIP },
        { P_KICK_FOUR }, { P_KICK_FOUR }, { P_KICK_FOUR }, { P_KICK_SKIP },
        { P_KICK_FOUR }, { P_KICK_FOUR }, { P_KICK_FOUR }, { P_KICK_SKIP } },
    [T_PERC] = {
        { P_PERC_BEAT }, { P_PERC_BEAT }, { P_PERC_BEAT }, { P_PERC_METAL },
        { P_PERC_BEAT }, { P_PERC_BEAT }, { P_PERC_BEAT }, { P_PERC_FILL },
        { P_PERC_BEAT }, { P_PERC_METAL }, { P_PERC_BEAT }, { P_PERC_METAL },
        { P_PERC_BEAT }, { P_PERC_METAL }, { P_PERC_BEAT }, { P_PERC_FILL } },
    [T_BASS] = {
        { P_BASS_DRIVE, 0, I_BASS }, { P_BASS_TURN, 0, I_BASS },
        { P_BASS_DRIVE, -4, I_BASS }, { P_BASS_DRIVE, -4, I_BASS },
        { P_BASS_DRIVE, -7, I_BASS }, { P_BASS_DRIVE, -7, I_BASS },
        { P_BASS_DRIVE, -5, I_BASS }, { P_BASS_TURN, -5, I_BASS },
        { P_BASS_DRIVE, 0, I_BASS }, { P_BASS_TURN, 0, I_BASS },
        { P_BASS_DRIVE, -4, I_BASS }, { P_BASS_DRIVE, -4, I_BASS },
        { P_BASS_DRIVE, -7, I_BASS }, { P_BASS_DRIVE, -7, I_BASS },
        { P_BASS_DRIVE, -5, I_BASS }, { P_BASS_TURN, -5, I_BASS } },
    [T_STAB] = {
        { P_STAB_332, AM }, { P_STAB_332, AM }, { P_STAB_332, FM }, { P_STAB_PUSH, FM },
        { P_STAB_332, DM }, { P_STAB_332, DM }, { P_STAB_332, EM }, { P_STAB_PUSH, EM },
        { P_STAB_332, AM }, { P_STAB_332, AM }, { P_STAB_332, FM }, { P_STAB_PUSH, FM },
        { P_STAB_332, DM }, { P_STAB_332, DM }, { P_STAB_332, EM }, { P_STAB_PUSH, EM } },
    [T_LEAD] = {
        { P_SILENT }, { P_SILENT }, { P_SILENT }, { P_SILENT },
        { P_SILENT }, { P_SILENT }, { P_SILENT }, { P_SILENT },
        { P_LEAD_1, 0, I_LEAD }, { P_LEAD_2, 0, I_LEAD }, { P_LEAD_3, 0, I_LEAD }, { P_LEAD_4, 0, I_LEAD },
        { P_LEAD_5, 0, I_LEAD }, { P_LEAD_6, 0, I_LEAD }, { P_LEAD_7, 0, I_LEAD }, { P_LEAD_8, 0, I_LEAD } },
};

/* ---- the sequencer --------------------------------------------------------- */

static small_t playing, step_timer, step, bar_no;
uint8_t music_mute;                         /* tracks not to play (1 << T_*): tools */
static small_t koff_held;                   /* KOFF is set: clear it next frame */
static const instrument *voice_inst[8];     /* what each voice is set up as */

/* low-pass echo filter (unity gain: the coefficients sum to 128) */
static const int8_t echo_fir[8] = { 0x0C, 0x21, 0x2B, 0x2B, 0x13, -2, -13, -7 };

void music_init(void)
{
    dsp(DSP_KOFF, MUSIC_VOICES);
    koff_held = 1;
    dsp(DSP_EVOLL, 0);
    dsp(DSP_EVOLR, 0);
    dsp(DSP_EFB, 0);
    dsp(DSP_ESA, 0x70);                     /* echo buffer at $7000 ... */
    dsp(DSP_EDL, 15);                       /* ... 240 ms: about an 8th note */
    for (small_t i = 0; i < 8; i++)
        dsp(DSP_FIR(i), echo_fir[i]);
    dsp(DSP_EON, ECHO_VOICES);
    dsp(DSP_FLG, 0);                        /* echo writes on (sound.c keeps it so) */
}

void music_start(void)
{
    playing = 1;
    step = 0;
    bar_no = 0;
    step_timer = 2;                         /* KOFF clears first (music_update) */
    for (small_t v = 0; v < 8; v++)
        voice_inst[v] = 0;
    dsp(DSP_EFB, 0x40);                     /* the echo buffer is clean by now */
    dsp(DSP_EVOLL, 0x22);
    dsp(DSP_EVOLR, 0x22);
}

void music_stop(void)
{
    playing = 0;
    dsp(DSP_KOFF, MUSIC_VOICES);
    koff_held = 1;
}

/* the step's value on track t */
#define STEP_OF(t) (pattern[song[t][bar_no].pattern][step])

/* set up and pitch the voice for one track's note; returns its KON bit */
static small_t track_note(small_t t, small_t v)
{
    const bar *b = &song[t][bar_no];
    small_t voice = track_voice[t];
    const instrument *in;
    uint16_t pitch;
    if (t == T_KICK || t == T_PERC) {
        in = &inst[DRUM_INST(v)];
        pitch = in->fixed_pitch;
    } else {
        in = &inst[b->inst];
        pitch = note_pitch[v - NOTE_FIRST + b->transpose] >> in->pitch_shift;
    }
    small_t base = voice << 4;
    const instrument *was = voice_inst[voice];
    if (was != in) {                    /* write only what differs (drums share envelopes) */
        voice_inst[voice] = in;
        if (!was || was->sample != in->sample)
            dsp(base | V_SRCN, in->sample);
        if (!was || was->adsr1 != in->adsr1)
            dsp(base | V_ADSR1, in->adsr1);
        if (!was || was->adsr2 != in->adsr2)
            dsp(base | V_ADSR2, in->adsr2);
        if (!was || was->vol_l != in->vol_l)
            dsp(base | V_VOLL, in->vol_l);
        if (!was || was->vol_r != in->vol_r)
            dsp(base | V_VOLR, in->vol_r);
    }
    dsp(base | V_PITCHL, pitch);
    dsp(base | V_PITCHH, pitch >> 8);
    return 1 << voice;
}

static void play_step(void)
{
    /* releases: KOFF is a level that blocks key-on while set, and the DSP
     * samples it only every other output sample, so it is raised here and
     * cleared a frame later (music_update), never just before a KON */
    small_t koff = 0;
    for (small_t t = 0; t < TRACKS; t++)
        if (STEP_OF(t) == xx)
            koff |= 1 << track_voice[t];
    if (koff) {
        dsp(DSP_KOFF, koff);
        koff_held = 1;
    }
    small_t kon = 0;
    for (small_t t = 0; t < TRACKS; t++) {
        small_t v = STEP_OF(t);
        if (v != __ && v != xx && !(music_mute & (1 << t)))
            kon |= track_note(t, v);
    }
    if (kon)
        dsp(DSP_KON, kon);
}

void music_update(void)
{
    if (koff_held && playing) {
        dsp(DSP_KOFF, 0);
        koff_held = 0;
    }
    if (!playing || --step_timer)
        return;
    step_timer = STEP_FRAMES;
    play_step();
    if (++step == STEPS) {
        step = 0;
        if (++bar_no == SONG_BARS)
            bar_no = 0;
    }
}
