/* The assembly core (core.s): what C may call and share with it. */
#ifndef CORE_H
#define CORE_H

#include <stdint.h>

/* ---- frame handshake with the NMI (spec/FrameSync.tla) -------------------
 * The main loop sets frame_ready = 1 when the shadow buffers below are
 * complete, then waits until the NMI has uploaded them and cleared it. */
extern volatile uint8_t frame_ready;
extern volatile uint8_t nmi_count;
extern uint8_t bg1_dirty, bg3_dirty;     /* upload BG1 rows 3..26 / BG3 rows 0..27 */
extern uint8_t tm_val;                   /* main-screen layer mask, written to TM  */
extern uint8_t bright;                   /* INIDISP value                          */
extern uint16_t scr_h, scr_v;            /* BG1/BG2 scroll (screen shake)          */
extern uint8_t fl_r, fl_g, fl_b;         /* colour-math flash, 0..31 per channel   */
extern uint8_t oam_buf[512];             /* sprite table shadow ...                */
extern uint8_t oam_hi[32];               /* ... and its high table                 */

/* tilemap shadows and the trail list live in high WRAM ($7E2000+) */
extern __far uint16_t bg1map[1024];
extern __far uint16_t bg3map[1024];
extern __far uint16_t trail[3072];

/* ---- the field ------------------------------------------------------------
 * 60 x 48 cells of 4x4 pixels, stored 64 per row (cell index = y*64 + x),
 * with two rows of padding above and below and four padding columns, all
 * C_CLAIM, so neighbours of any field cell can be read without bounds checks. */
#define FIELD_W  60
#define FIELD_H  48
#define INTERIOR (58 * 46)
enum { C_OPEN = 0, C_CLAIM = 1, C_EDGE = 2, C_TRAIL = 3 };
extern uint8_t grid[48 * 64];

void     field_init(void);                     /* border edges, open interior      */
uint16_t field_fill(uint16_t seed_cell);       /* claim all not reachable from the  */
                                               /* seed; trail -> claimed; edges     */
                                               /* recomputed; returns cells claimed */
void     field_redraw_all(void);               /* rebuild the BG1 shadow from grid  */
void     field_update_cell(uint16_t cell);     /* re-tile one cell into the shadow  */

/* collision: OR of (1 << state) over the cells under a box (field pixels) */
extern uint8_t bx0, bx1, by0, by1;
uint16_t box_scan(void);
#define F_OPEN  1
#define F_CLAIM 2
#define F_EDGE  4
#define F_TRAIL 8

/* ---- PPU uploads (forced blank only, NMI off) ------------------------------ */
void core_boot_ppu(void);          /* reset all PPU registers                  */
void load_static(void);            /* tiles, font, sprites, palettes, PPU setup */
void load_picture(uint16_t n);     /* stage picture n (0..3) into BG2           */
void upload_bg1(void);
void upload_bg3(void);
void upload_oam(void);
extern const __far uint16_t title_map[54];     /* 18 x 3 logo tiles for BG3 */

/* ---- sound CPU (spec/ApuHandshake.tla) ------------------------------------- */
void spc_init(void);               /* upload the driver, init the DSP           */
void apu_write(uint16_t reg_val);  /* DSP register (high byte) := value (low)   */
extern uint8_t apu_dead;           /* set if the SPC700 stopped answering        */

#endif
