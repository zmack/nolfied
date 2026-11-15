; =============================================================================
;  NOLFIED - assembly core (Calypsi as65816)
;
;  Only what has to be assembly lives here: boot, the NMI handler, DMA
;  uploads, the field kernels (flood fill, tile rebuild, collision scan) and
;  the SPC700 handshake. Everything else is C (the .c files in src).
;
;  Conventions
;  - Kernels (the *_k routines and the routines carried over from the legacy
;    ca65 source) run with 8-bit A and 16-bit X/Y, as in legacy/main.s.
;  - C calls only the wrappers at the end ("C interface"): Calypsi calls with
;    16-bit A/X/Y, the first argument in A (16 bits), and the result in A.
;  - The direct page is 0 and the data bank 0 (small data model), so near
;    variables are reached with absolute addressing.
;  - The NMI touches only the variables in the "frame" block below; the frame
;    handshake is modelled in spec/FrameSync.tla.
; =============================================================================

INIDISP         .equ 0x2100
OBSEL           .equ 0x2101
OAMADDL         .equ 0x2102
OAMADDH         .equ 0x2103
BGMODE          .equ 0x2105
BG1SC           .equ 0x2107
BG2SC           .equ 0x2108
BG3SC           .equ 0x2109
BG12NBA         .equ 0x210B
BG34NBA         .equ 0x210C
BG1HOFS         .equ 0x210D
BG1VOFS         .equ 0x210E
BG2HOFS         .equ 0x210F
BG2VOFS         .equ 0x2110
BG3HOFS         .equ 0x2111
BG3VOFS         .equ 0x2112
VMAIN           .equ 0x2115
VMADDL          .equ 0x2116
CGADD           .equ 0x2121
CGDATA          .equ 0x2122
TM              .equ 0x212C
CGWSEL          .equ 0x2130
CGADSUB         .equ 0x2131
COLDATA         .equ 0x2132
APUIO0          .equ 0x2140
APUIO1          .equ 0x2141
APUIO2          .equ 0x2142
APUIO3          .equ 0x2143
WMADDL          .equ 0x2181
WMADDM          .equ 0x2182
WMADDH          .equ 0x2183
NMITIMEN        .equ 0x4200
WRDIVL          .equ 0x4204
WRDIVB          .equ 0x4206
MDMAEN          .equ 0x420B
HDMAEN          .equ 0x420C
RDNMI           .equ 0x4210
RDDIVL          .equ 0x4214
RDMPYL          .equ 0x4216
DMAP0           .equ 0x4300
BBAD0           .equ 0x4301
A1T0L           .equ 0x4302
A1B0            .equ 0x4304
DAS0L           .equ 0x4305

FIELD_W         .equ 60
FIELD_H         .equ 48
C_OPEN          .equ 0
C_CLAIM         .equ 1
C_EDGE          .equ 2
C_TRAIL         .equ 3
F_CLAIM         .equ 2
F_EDGE          .equ 4
F_TRAIL         .equ 8

; ---- frame block: shared by the main loop (C) and the NMI ------------------
              .section ztiny,bss
              .public nmi_count, frame_ready, bg1_dirty, bg3_dirty, tm_val, bright
nmi_count:    .space  1
frame_ready:  .space  1
bg1_dirty:    .space  1
bg3_dirty:    .space  1
tm_val:       .space  1
bright:       .space  1
; ---- kernel scratch (direct page) -------------------------------------------
              .public bx0, bx1, by0, by1, newly
dma_src:      .space  3
dma_len:      .space  2
t_x:          .space  2
t_y:          .space  2
ut_tmp:       .space  2
bx0:          .space  1
bx1:          .space  1
by0:          .space  1
by1:          .space  1
cx0:          .space  1
cx1:          .space  1
cy0:          .space  1
cy1:          .space  1
ccx:          .space  1
bflags:       .space  1
bs_tmp:       .space  2
bs_w:         .space  1
bs_h:         .space  1
tmp2:         .space  2
noseed:       .space  1
newly:        .space  2
apu_cnt:      .space  1
apu_reg:      .space  1
apu_val:      .space  1
enx:          .space  2
eslot:        .space  2
ct_i:         .space  2                 ; field_clear_trail: byte offset
ct_end:       .space  2
pr_base:      .space  2                 ; print: attribute << 8, less ' '

              .section znear,bss
              .public scr_h, scr_v, fl_r, fl_g, fl_b, apu_dead, oam_buf, oam_hi
              .public grid_mem, grid
scr_h:        .space  2
scr_v:        .space  2
fl_r:         .space  1
fl_g:         .space  1
fl_b:         .space  1
apu_dead:     .space  1
oam_buf:      .space  512
oam_hi:       .space  32
; field grid: 48 rows of 64 cells (60 used), two padding rows above and below
; BG3 (text) tilemap shadow: bank 0, so C writes it with plain absolute
; stores (from high WRAM every character cost a 24-bit indexed store)
              .public bg3map
bg3map:       .space  2048
grid_mem:     .space  0x80
grid:         .space  48*64
              .space  0x80

              .section zfar,bss
              .public bg1map, trail
bg1map:       .space  2048          ; BG1 tilemap shadow
trail:        .space  6144          ; trail cell list (words)
flood:        .space  6144          ; flood fill stack (words)

              .section code
              .extern e_x, e_y, e_vx, e_vy, e_half
nmi:
              rep     #0x30
              pha
              phx
              phy
              phb
              phd
              lda     ##0
              tcd
              sep     #0x20
              lda     #0x00
              pha
              plb
              lda     RDNMI
              lda     dp:.tiny (frame_ready)
              bne     nmi_a0
              jmp     done
nmi_a0:
               ; OAM
              stz     OAMADDL
              stz     OAMADDH
              stz     DMAP0
              lda     #0x04
              sta     BBAD0
              ldx     ##oam_buf
              stx     A1T0L
              stz     A1B0
              ldx     ##544
              stx     DAS0L
              lda     #0x01
              sta     MDMAEN
               ; BG1 field rows 3..26
              lda     dp:.tiny (bg1_dirty)
              beq     nobg1
              lda     #0x80
              sta     VMAIN
              ldx     ##(0x5000 + 3*32)
              stx     VMADDL
              lda     #0x01
              sta     DMAP0
              lda     #0x18
              sta     BBAD0
              ldx     ##.word0 (bg1map + 3*64)
              stx     A1T0L
              lda     #.byte2 bg1map
              sta     A1B0
              ldx     ##(24*64)
              stx     DAS0L
              lda     #0x01
              sta     MDMAEN
              stz     dp:.tiny (bg1_dirty)
nobg1:
              lda     dp:.tiny (bg3_dirty)
              beq     nobg3
              lda     #0x80
              sta     VMAIN
              ldx     ##0x5800
              stx     VMADDL
              lda     #0x01
              sta     DMAP0
              lda     #0x18
              sta     BBAD0
              ldx     ##.word0 (bg3map)
              stx     A1T0L
              lda     #.byte2 bg3map
              sta     A1B0
              ldx     ##(28*64)
              stx     DAS0L
              lda     #0x01
              sta     MDMAEN
              stz     dp:.tiny (bg3_dirty)
nobg3:
               ; cycle the trail colour (CGRAM 36)
              lda     #36
              sta     CGADD
              rep     #0x20
              lda     dp:.tiny (nmi_count)
              lsr     a
              and     ##0x000E
              tax
              sep     #0x20
              lda     trail_cols,x
              sta     CGDATA
              lda     trail_cols+1,x
              sta     CGDATA
              lda     scr_h
              sta     BG1HOFS
              lda     scr_h+1
              sta     BG1HOFS
              lda     scr_h
              sta     BG2HOFS
              lda     scr_h+1
              sta     BG2HOFS
              lda     scr_v
              sta     BG1VOFS
              lda     scr_v+1
              sta     BG1VOFS
              lda     scr_v
              sta     BG2VOFS
              lda     scr_v+1
              sta     BG2VOFS
              lda     fl_r
              ora     #0x20
              sta     COLDATA
              lda     fl_g
              ora     #0x40
              sta     COLDATA
              lda     fl_b
              ora     #0x80
              sta     COLDATA
              lda     dp:.tiny (tm_val)
              sta     TM
              lda     dp:.tiny (bright)
              sta     INIDISP
              stz     dp:.tiny (frame_ready)
done:
              inc     dp:.tiny (nmi_count)
              rep     #0x30
              pld
              plb
              ply
              plx
              pla
              rti

init_ppu:
              lda     #0x80
              sta     INIDISP
              ldx     ##0x2101
init_ppu_a:   stz     0x0000,x
              inx
              cpx     ##0x210D
              bne     init_ppu_a
init_ppu_b:   stz     0x0000,x ; scroll regs: write twice
              stz     0x0000,x
              inx
              cpx     ##0x2115
              bne     init_ppu_b
              lda     #0x80
              sta     VMAIN
              stz     0x2116
              stz     0x2117
              stz     0x211A
              stz     0x211B
              lda     #0x01
              sta     0x211B
              stz     0x211C
              stz     0x211C
              stz     0x211D
              stz     0x211D
              stz     0x211E
              sta     0x211E
              stz     0x211F
              stz     0x211F
              stz     0x2120
              stz     0x2120
              stz     0x2121
              ldx     ##0x2123
init_ppu_c:   stz     0x0000,x
              inx
              cpx     ##0x2134
              bne     init_ppu_c
              lda     #0xFF
              sta     0x4201
              ldx     ##0x4202
init_ppu_d:   stz     0x0000,x
              inx
              cpx     ##0x420E
              bne     init_ppu_d
              rts

dma_to_vram:
              lda     #0x80
              sta     VMAIN
              stx     VMADDL
              lda     #0x01
              sta     DMAP0
              lda     #0x18
              sta     BBAD0
              ldx     dp:.tiny (dma_src)
              stx     A1T0L
              lda     dp:.tiny (dma_src+2)
              sta     A1B0
              ldx     dp:.tiny (dma_len)
              stx     DAS0L
              lda     #0x01
              sta     MDMAEN
              rts

dma_to_cgram:
              sta     CGADD
              stz     DMAP0
              lda     #0x22
              sta     BBAD0
              ldx     dp:.tiny (dma_src)
              stx     A1T0L
              lda     dp:.tiny (dma_src+2)
              sta     A1B0
              ldx     dp:.tiny (dma_len)
              stx     DAS0L
              lda     #0x01
              sta     MDMAEN
              rts

load_static_k:
              ldx     ##.word0 (bg_tiles)
              stx     dp:.tiny (dma_src)
              lda     #.byte2 bg_tiles
              sta     dp:.tiny (dma_src+2)
              ldx     ##8192
              stx     dp:.tiny (dma_len)
              ldx     ##0x0000
              jsr     dma_to_vram
              ldx     ##.word0 (font_tiles)
              stx     dp:.tiny (dma_src)
              lda     #.byte2 font_tiles
              sta     dp:.tiny (dma_src+2)
              ldx     ##(font_end - font_tiles)
              stx     dp:.tiny (dma_len)
              ldx     ##0x4000
              jsr     dma_to_vram
              ldx     ##.word0 (obj_tiles)
              stx     dp:.tiny (dma_src)
              lda     #.byte2 obj_tiles
              sta     dp:.tiny (dma_src+2)
              ldx     ##4096
              stx     dp:.tiny (dma_len)
              ldx     ##0x6000
              jsr     dma_to_vram
              ldx     ##.word0 (icon_tiles)
              stx     dp:.tiny (dma_src)
              lda     #.byte2 icon_tiles
              sta     dp:.tiny (dma_src+2)
              ldx     ##8192
              stx     dp:.tiny (dma_len)
              ldx     ##0x7000
              jsr     dma_to_vram
              ldx     ##.word0 (mini_tiles)
              stx     dp:.tiny (dma_src)
              lda     #.byte2 mini_tiles
              sta     dp:.tiny (dma_src+2)
              ldx     ##256
              stx     dp:.tiny (dma_len)
              ldx     ##0x43C0
              jsr     dma_to_vram
              ldx     ##.word0 (bg3_pal)
              stx     dp:.tiny (dma_src)
              lda     #.byte2 bg3_pal
              sta     dp:.tiny (dma_src+2)
              ldx     ##48
              stx     dp:.tiny (dma_len)
              lda     #0
              jsr     dma_to_cgram
              ldx     ##.word0 (bg1_pal)
              stx     dp:.tiny (dma_src)
              lda     #.byte2 bg1_pal
              sta     dp:.tiny (dma_src+2)
              ldx     ##32
              stx     dp:.tiny (dma_len)
              lda     #32
              jsr     dma_to_cgram
              ldx     ##.word0 (card_pals)
              stx     dp:.tiny (dma_src)
              lda     #.byte2 card_pals
              sta     dp:.tiny (dma_src+2)
              ldx     ##96
              stx     dp:.tiny (dma_len)
              lda     #64
              jsr     dma_to_cgram
              ldx     ##.word0 (obj_pal)
              stx     dp:.tiny (dma_src)
              lda     #.byte2 obj_pal
              sta     dp:.tiny (dma_src+2)
              ldx     ##128
              stx     dp:.tiny (dma_len)
              lda     #128
              jsr     dma_to_cgram
              ldx     ##.word0 (icon_pal)
              stx     dp:.tiny (dma_src)
              lda     #.byte2 icon_pal
              sta     dp:.tiny (dma_src+2)
              ldx     ##32
              stx     dp:.tiny (dma_len)
              lda     #192
              jsr     dma_to_cgram
              stz     CGWSEL ; colour math: add fixed colour (screen flashes)
              lda     #0x3F
              sta     CGADSUB
              lda     #0xE0
              sta     COLDATA
              ldx     ##0x03FF
              stx     scr_v
              lda     #0x09 ; mode 1, BG3 high priority
              sta     BGMODE
              lda     #0x50
              sta     BG1SC
              lda     #0x54
              sta     BG2SC
              lda     #0x58
              sta     BG3SC
              lda     #0x10
              sta     BG12NBA
              lda     #0x04
              sta     BG34NBA
              lda     #0x63 ; 16x16/32x32 sprites at VRAM $6000
              sta     OBSEL
              stz     BG1HOFS
              stz     BG1HOFS
              stz     BG2HOFS
              stz     BG2HOFS
              stz     BG3HOFS
              stz     BG3HOFS
              lda     #0xFF
              sta     BG1VOFS
              sta     BG1VOFS
              sta     BG2VOFS
              sta     BG2VOFS
              sta     BG3VOFS
              sta     BG3VOFS
              lda     #0x17
              sta     dp:.tiny (tm_val)
              sta     TM
              lda     #0x0F
              sta     dp:.tiny (bright)
              rts

upload_bg1_k:
              ldx     ##.word0 (bg1map)
              stx     dp:.tiny (dma_src)
              lda     #.byte2 bg1map
              sta     dp:.tiny (dma_src+2)
              ldx     ##2048
              stx     dp:.tiny (dma_len)
              ldx     ##0x5000
              jmp     dma_to_vram

upload_bg3_k:
              ldx     ##.word0 (bg3map)
              stx     dp:.tiny (dma_src)
              lda     #.byte2 bg3map
              sta     dp:.tiny (dma_src+2)
              ldx     ##2048
              stx     dp:.tiny (dma_len)
              ldx     ##0x5800
              jmp     dma_to_vram

upload_oam_k:
              stz     OAMADDL
              stz     OAMADDH
              stz     DMAP0
              lda     #0x04
              sta     BBAD0
              ldx     ##oam_buf
              stx     A1T0L
              stz     A1B0
              ldx     ##544
              stx     DAS0L
              lda     #0x01
              sta     MDMAEN
              rts

load_picture_k:
              rep     #0x20
              and     ##0x0003
              asl     a
              tax
              lda     pic_chr_lo,x
              sta     dp:.tiny (dma_src)
              lda     pic_chr_len,x
              sta     dp:.tiny (dma_len)
              sep     #0x20
              lda     pic_bank,x
              sta     dp:.tiny (dma_src+2)
              phx
              ldx     ##0x1000
              jsr     dma_to_vram
              plx
              rep     #0x20
              lda     pic_map_lo,x
              sta     dp:.tiny (dma_src)
              lda     ##2048
              sta     dp:.tiny (dma_len)
              sep     #0x20
              phx
              ldx     ##0x5400
              jsr     dma_to_vram
              plx
              rep     #0x20
              lda     pic_pal_lo,x
              sta     dp:.tiny (dma_src)
              lda     ##32
              sta     dp:.tiny (dma_len)
              sep     #0x20
              lda     #48
              jmp     dma_to_cgram

init_field:
              ldx     ##0x0000
              lda     #C_CLAIM
init_field_pad:sta     grid_mem,x
              inx
              cpx     ##0x0D00
              bne     init_field_pad
              ldx     ##0x0000
init_field_c: rep     #0x20
              txa
              and     ##0x003F
              cmp     ##FIELD_W
              bcs     init_field_next
              tay
              txa
              lsr     a
              lsr     a
              lsr     a
              lsr     a
              lsr     a
              lsr     a
              sep     #0x20
              cmp     #0
              beq     init_field_border
              cmp     #(FIELD_H-1)
              beq     init_field_border
              cpy     ##0
              beq     init_field_border
              cpy     ##(FIELD_W-1)
              beq     init_field_border
              lda     #C_OPEN
              bra     init_field_st
init_field_border:
              lda     #C_EDGE
init_field_st:sta     grid,x
init_field_next:sep     #0x20
              inx
              cpx     ##(FIELD_H*64)
              bne     init_field_c
              rts

update_tile_txy:
              rep     #0x20
              lda     dp:.tiny (t_y)
              and     ##0x00FF
              xba
              lsr     a
              sta     dp:.tiny (ut_tmp)
              lda     dp:.tiny (t_x)
              and     ##0x00FF
              asl     a
              clc
              adc     dp:.tiny (ut_tmp)
              tax ; X = top-left cell
              lda     dp:.tiny (t_y)
              and     ##0x00FF
              asl     a
              asl     a
              asl     a
              asl     a
              asl     a
              asl     a
              sta     dp:.tiny (ut_tmp)
              lda     dp:.tiny (t_x)
              and     ##0x00FF
              asl     a
              clc
              adc     dp:.tiny (ut_tmp)
              adc     ##(3*64 + 2)
              tay ; Y = map offset
              sep     #0x20
              lda     grid+65,x
              asl     a
              asl     a
              ora     grid+64,x
              asl     a
              asl     a
              ora     grid+1,x
              asl     a
              asl     a
              ora     grid,x
              sta     dp:.tiny (ut_tmp)
              tyx
              sta     long:bg1map,x
              lda     #0x08 ; palette 2
              sta     long:bg1map+1,x
              lda     #0x01
              sta     dp:.tiny (bg1_dirty)
              rts

update_cell:
              rep     #0x20
              txa
              and     ##0x003F
              lsr     a
              sta     dp:.tiny (t_x)
              txa
              asl     a
              xba
              and     ##0x00FF
              sta     dp:.tiny (t_y)
              sep     #0x20
              jmp     update_tile_txy

redraw_all:
              rep     #0x20
              lda     ##(85 | 0x0800) ; fully transparent tile outside the field
              ldx     ##0x0000
redraw_all_f: sta     long:bg1map,x
              inx
              inx
              cpx     ##2048
              bne     redraw_all_f
              stz     dp:.tiny (t_y)
redraw_all_y: stz     dp:.tiny (t_x)
redraw_all_x: sep     #0x20
              jsr     update_tile_txy
              rep     #0x20
              inc     dp:.tiny (t_x)
              lda     dp:.tiny (t_x)
              cmp     ##30
              bne     redraw_all_x
              inc     dp:.tiny (t_y)
              lda     dp:.tiny (t_y)
              cmp     ##24
              bne     redraw_all_y
              sep     #0x20
              lda     #0x01
              sta     dp:.tiny (bg1_dirty)
              rts

box_scan_k:
              lda     dp:.tiny (bx0)
              cmp     #240
              bcc     box_scan_k_a0
              lda     #0
box_scan_k_a0:  lsr     a
              lsr     a
              sta     dp:.tiny (cx0)
              lda     dp:.tiny (bx1)
              cmp     #240
              bcc     box_scan_k_a1
              lda     #239
box_scan_k_a1:  lsr     a
              lsr     a
              sta     dp:.tiny (cx1)
              lda     dp:.tiny (by0)
              cmp     #192
              bcc     box_scan_k_a2
              lda     #0
box_scan_k_a2:  lsr     a
              lsr     a
              sta     dp:.tiny (cy0)
              lda     dp:.tiny (by1)
              cmp     #192
              bcc     box_scan_k_a3
              lda     #191
box_scan_k_a3:  lsr     a
              lsr     a
              sta     dp:.tiny (cy1)
; The scan: at least one row and one column (as in legacy box_scan, whose
; loops test for the end after the first cell), cx0..cx1 by cy0..cy1. Not
; the legacy code any more: the inner loop stays 8-bit, counts down, and
; keeps B = 0 so that tay gives a clean 16-bit index (about 30 cycles a
; cell instead of 45). tools/test_selftest.py checks it against a model.
              stz     dp:.tiny (bflags)
              lda     dp:.tiny (cx1)
              sec
              sbc     dp:.tiny (cx0)
              bcs     box_scan_k_w
              lda     #0
box_scan_k_w: inc     a
              sta     dp:.tiny (bs_w)           ; columns per row
              lda     dp:.tiny (cy1)
              sec
              sbc     dp:.tiny (cy0)
              bcs     box_scan_k_h
              lda     #0
box_scan_k_h: inc     a
              sta     dp:.tiny (bs_h)           ; rows
              rep     #0x20
              lda     dp:.tiny (cy0)
              and     ##0x00FF
              asl     a
              asl     a
              asl     a
              asl     a
              asl     a
              asl     a
              sta     dp:.tiny (bs_tmp)
              lda     dp:.tiny (cx0)
              and     ##0x00FF
              clc
              adc     dp:.tiny (bs_tmp)
              tax                               ; X = first cell
              lda     dp:.tiny (bs_w)
              and     ##0x00FF
              eor     ##0xFFFF
              sec
              adc     ##64
              sta     dp:.tiny (bs_tmp)         ; 64 - columns: on to the next row
              sep     #0x20
box_scan_k_row: lda   #0
              xba                               ; B = 0: tay below is clean
              lda     dp:.tiny (bs_w)
              sta     dp:.tiny (ccx)            ; columns left in this row
box_scan_k_col: lda   grid,x
              and     #0x07
              tay
              lda     bit_tab,y
              tsb     dp:.tiny (bflags)
              inx
              dec     dp:.tiny (ccx)
              bne     box_scan_k_col
              rep     #0x20
              txa
              clc
              adc     dp:.tiny (bs_tmp)
              tax
              sep     #0x20
              dec     dp:.tiny (bs_h)
              bne     box_scan_k_row
              lda     dp:.tiny (bflags)
              rts

spc_init_k:
              ldx     ##0x0000
              rep     #0x20
spc_init_k_w:   lda     APUIO0
              cmp     ##0xBBAA
              beq     spc_init_k_a0
              dex
              bne     spc_init_k_w
              sep     #0x20
              bra     spc_init_k_dead
spc_init_k_a0:  sep     #0x20
              ldx     ##0x0200
              stx     APUIO2
              lda     #0x01
              sta     APUIO1
              lda     #0xCC
              sta     APUIO0
spc_init_k_w1:  cmp     APUIO0
              bne     spc_init_k_w1
              ldy     ##0x0000
spc_init_k_l:   lda     spc_blob,y
              sta     APUIO1
              tya
              sta     APUIO0
spc_init_k_w2:  cmp     APUIO0
              bne     spc_init_k_w2
              iny
              cpy     ##(spc_blob_end - spc_blob)
              bne     spc_init_k_l
              ldx     ##0x0200
              stx     APUIO2
              stz     APUIO1
              tya
              clc
              adc     #1
              bne     spc_init_k_a1
              inc     a
spc_init_k_a1:  sta     APUIO0
spc_init_k_w3:  cmp     APUIO0
              bne     spc_init_k_w3
              sta     dp:.tiny (apu_cnt)
               ; wait for the driver to latch port0 and raise READY before the first
               ; request, otherwise it can mistake that request for an old one
              ldx     ##0x0000
spc_init_k_w4:  lda     APUIO1
              cmp     #0xA5
              beq     spc_init_k_up
              dex
              bne     spc_init_k_w4
spc_init_k_dead:lda     #1
              sta     apu_dead
              rts
spc_init_k_up:
              lda     #0x6C
              sta     dp:.tiny (apu_reg)
              lda     #0x20
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x0C
              sta     dp:.tiny (apu_reg)
              lda     #0x60
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x1C
              sta     dp:.tiny (apu_reg)
              lda     #0x60
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x2C
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x3C
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x4D
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x3D
              sta     dp:.tiny (apu_reg)
              lda     #0x02
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x2D
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x5D
              sta     dp:.tiny (apu_reg)
              lda     #0x03
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x6D
              sta     dp:.tiny (apu_reg)
              lda     #0x70
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x7D
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x5C
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x04
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x05
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x07
              sta     dp:.tiny (apu_reg)
              lda     #0x7F
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x00
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x01
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x14
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x15
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x17
              sta     dp:.tiny (apu_reg)
              lda     #0x7F
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x10
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x11
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x24
              sta     dp:.tiny (apu_reg)
              lda     #0x01
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x25
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x27
              sta     dp:.tiny (apu_reg)
              lda     #0x7F
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x20
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x21
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x34
              sta     dp:.tiny (apu_reg)
              lda     #0x01
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x35
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x37
              sta     dp:.tiny (apu_reg)
              lda     #0x7F
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x30
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              lda     #0x31
              sta     dp:.tiny (apu_reg)
              lda     #0x00
              sta     dp:.tiny (apu_val)
              jsr     apu_write_k
              rts

apu_write_k:
              lda     apu_dead
              beq     apu_write_k_a0
              rts
apu_write_k_a0: phx
              lda     dp:.tiny (apu_reg)
              sta     APUIO1
              lda     dp:.tiny (apu_val)
              sta     APUIO2
              inc     dp:.tiny (apu_cnt)
              lda     dp:.tiny (apu_cnt)
              sta     APUIO0
              ldx     ##0x0800
apu_write_k_w:  cmp     APUIO0
              beq     apu_write_k_ok
              dex
              bne     apu_write_k_w
              lda     #1 ; no echo: the driver may still be reading the
              sta     apu_dead ; ports, so never write them again
apu_write_k_ok: plx
              rts

field_fill_k:
              stz     dp:.tiny (noseed)
              ; (seed cell index arrives in Y)
              sty     dp:.tiny (tmp2)
              lda     grid,y
              beq     field_fill_k_seed
              ldx     ##0x0000
field_fill_k_try:rep     #0x20
              lda     dp:.tiny (tmp2)
              clc
              adc     seed_offs,x
              tay
              sep     #0x20
              lda     grid,y
              beq     field_fill_k_seed
              inx
              inx
              cpx     ##(seed_offs_end - seed_offs)
              bne     field_fill_k_try
              lda     #0x01
              sta     dp:.tiny (noseed)
              jmp     field_fill_k_pass
field_fill_k_seed:lda     #4
              sta     grid,y
              rep     #0x20
              tya
              sta     long:flood
              ldx     ##0x0002
field_fill_k_pop:rep     #0x20
              cpx     ##0x0000
              beq     field_fill_k_fdone
              dex
              dex
              lda     long:flood,x
              tay
              sep     #0x20
              lda     grid-1,y
              bne     field_fill_k_n1
              lda     #4
              sta     grid-1,y
              rep     #0x20
              tya
              dec     a
              sta     long:flood,x
              inx
              inx
              sep     #0x20
field_fill_k_n1:lda     grid+1,y
              bne     field_fill_k_n2
              lda     #4
              sta     grid+1,y
              rep     #0x20
              tya
              inc     a
              sta     long:flood,x
              inx
              inx
              sep     #0x20
field_fill_k_n2:lda     grid-64,y
              bne     field_fill_k_n3
              lda     #4
              sta     grid-64,y
              rep     #0x20
              tya
              sec
              sbc     ##64
              sta     long:flood,x
              inx
              inx
              sep     #0x20
field_fill_k_n3:lda     grid+64,y
              bne     field_fill_k_pop
              lda     #4
              sta     grid+64,y
              rep     #0x20
              tya
              clc
              adc     ##64
              sta     long:flood,x
              inx
              inx
              bra     field_fill_k_pop
field_fill_k_fdone:sep     #0x20
field_fill_k_pass: ; convert: open (unreached) & trail -> claimed, reached -> open
              sep     #0x20
              ldx     ##0x0000
              stx     dp:.tiny (newly)
field_fill_k_p:lda     grid,x
              beq     field_fill_k_zero
              cmp     #C_TRAIL
              beq     field_fill_k_claim
              cmp     #4
              bne     field_fill_k_pn
              stz     grid,x
              bra     field_fill_k_pn
field_fill_k_zero:lda     dp:.tiny (noseed)
              bne     field_fill_k_pn
field_fill_k_claim:lda     #C_CLAIM
              sta     grid,x
              rep     #0x20
              inc     dp:.tiny (newly)
              sep     #0x20
field_fill_k_pn:inx
              cpx     ##(FIELD_H*64)
              bne     field_fill_k_p
               ; recompute edges: claimed cell touching an open cell (8-way)
              ldx     ##0x0000
field_fill_k_e:lda     grid,x
              beq     field_fill_k_en
              lda     grid-65,x
              beq     field_fill_k_edge
              lda     grid-64,x
              beq     field_fill_k_edge
              lda     grid-63,x
              beq     field_fill_k_edge
              lda     grid-1,x
              beq     field_fill_k_edge
              lda     grid+1,x
              beq     field_fill_k_edge
              lda     grid+63,x
              beq     field_fill_k_edge
              lda     grid+64,x
              beq     field_fill_k_edge
              lda     grid+65,x
              beq     field_fill_k_edge
              lda     #C_CLAIM
              sta     grid,x
              bra     field_fill_k_en
field_fill_k_edge:lda     #C_EDGE
              sta     grid,x
field_fill_k_en:inx
              cpx     ##(FIELD_H*64)
              bne     field_fill_k_e
              rts


; =============================================================================
;  Enemy kernels (legacy enemy_move, and the box half of enemy_collide)
;  X = slot * 2 (the enemy arrays e_x, e_y, e_vx, e_vy, e_half are words)
; =============================================================================
enemy_move_k:
               ; ---- horizontal
              rep     #0x20
              lda     e_x,x
              clc
              adc     e_vx,x
              sta     dp:.tiny (enx)
              sep     #0x20
              lda     e_vx+1,x
              bmi     enemy_move_k_lft
              lda     dp:.tiny (enx+1)
              clc
              adc     e_half,x
              bra     enemy_move_k_sx
enemy_move_k_lft:lda     dp:.tiny (enx+1)
              sec
              sbc     e_half,x
enemy_move_k_sx:sta     dp:.tiny (bx0)
              sta     dp:.tiny (bx1)
              lda     e_y+1,x
              sec
              sbc     e_half,x
              sta     dp:.tiny (by0)
              lda     e_y+1,x
              clc
              adc     e_half,x
              sta     dp:.tiny (by1)
              jsr     box_scan_k
              ldx     dp:.tiny (eslot)
              and     #(F_CLAIM|F_EDGE)
              beq     enemy_move_k_xok
              rep     #0x20
              lda     ##0x0000
              sec
              sbc     e_vx,x
              sta     e_vx,x
              sep     #0x20
              bra     enemy_move_k_yax
enemy_move_k_xok:rep     #0x20
              lda     dp:.tiny (enx)
              sta     e_x,x
              sep     #0x20
enemy_move_k_yax: ; ---- vertical
              rep     #0x20
              lda     e_y,x
              clc
              adc     e_vy,x
              sta     dp:.tiny (enx)
              sep     #0x20
              lda     e_vy+1,x
              bmi     enemy_move_k_up
              lda     dp:.tiny (enx+1)
              clc
              adc     e_half,x
              bra     enemy_move_k_sy
enemy_move_k_up:lda     dp:.tiny (enx+1)
              sec
              sbc     e_half,x
enemy_move_k_sy:sta     dp:.tiny (by0)
              sta     dp:.tiny (by1)
              lda     e_x+1,x
              sec
              sbc     e_half,x
              sta     dp:.tiny (bx0)
              lda     e_x+1,x
              clc
              adc     e_half,x
              sta     dp:.tiny (bx1)
              jsr     box_scan_k
              ldx     dp:.tiny (eslot)
              and     #(F_CLAIM|F_EDGE)
              beq     enemy_move_k_yok
              rep     #0x20
              lda     ##0x0000
              sec
              sbc     e_vy,x
              sta     e_vy,x
              sep     #0x20
              rts
enemy_move_k_yok:rep     #0x20
              lda     dp:.tiny (enx)
              sta     e_y,x
              sep     #0x20
              rts


enemy_box_k:
              lda     e_x+1,x
              sec
              sbc     e_half,x
              sta     dp:.tiny (bx0)
              lda     e_x+1,x
              clc
              adc     e_half,x
              sta     dp:.tiny (bx1)
              lda     e_y+1,x
              sec
              sbc     e_half,x
              sta     dp:.tiny (by0)
              lda     e_y+1,x
              clc
              adc     e_half,x
              sta     dp:.tiny (by1)
              jsr     box_scan_k
              rts

; =============================================================================
;  C interface (16-bit in, 16-bit out; argument and result in A)
; =============================================================================
              .public core_boot_ppu, load_static, load_picture, upload_bg1
              .public upload_bg3, upload_oam, field_init, field_fill
              .public field_redraw_all, field_update_cell, box_scan
              .public spc_init, apu_write, enemy_move, enemy_box_flags
              .public bg3_clear, print, field_clear_trail

; legacy kernels keep their names with a _k suffix where C sees a wrapper
core_boot_ppu: sep    #0x20
              jsr     init_ppu
              rep     #0x30
              rts

load_static:  sep     #0x20
              jsr     load_static_k
              rep     #0x30
              rts

load_picture: sep     #0x20                  ; A = picture number
              jsr     load_picture_k
              rep     #0x30
              rts

upload_bg1:   sep     #0x20
              jsr     upload_bg1_k
              rep     #0x30
              rts

upload_bg3:   sep     #0x20
              jsr     upload_bg3_k
              rep     #0x30
              rts

upload_oam:   sep     #0x20
              jsr     upload_oam_k
              rep     #0x30
              rts

field_init:   sep     #0x20
              jsr     init_field
              rep     #0x30
              rts

; uint16_t field_fill(uint16_t seed_cell): claims everything not reachable
; from seed_cell, returns the number of newly claimed cells
field_fill:   tay
              sep     #0x20
              jsr     field_fill_k
              rep     #0x30
              lda     dp:.tiny (newly)
              rts

field_redraw_all: sep #0x20
              jsr     redraw_all
              rep     #0x30
              rts

; void field_update_cell(uint16_t cell)
field_update_cell: tax
              sep     #0x20
              jsr     update_cell
              rep     #0x30
              rts

; uint16_t box_scan(void): OR of (1 << state) over the box bx0..bx1, by0..by1
box_scan:     sep     #0x20
              jsr     box_scan_k
              rep     #0x30
              and     ##0x00ff
              rts

; void enemy_move(uint16_t slot): one step, bouncing off claimed area
enemy_move:   asl     a
              tax
              stx     dp:.tiny (eslot)
              sep     #0x20
              jsr     enemy_move_k
              rep     #0x30
              rts

; uint16_t enemy_box_flags(uint16_t slot): cell flags under the enemy's box
enemy_box_flags: asl  a
              tax
              stx     dp:.tiny (eslot)
              sep     #0x20
              jsr     enemy_box_k
              rep     #0x30
              and     ##0x00ff
              rts

; uint16_t print(uint16_t at, const char *s, uint8_t attr): text into the
; BG3 shadow from index `at`; returns the index after it. s arrives in _Dp,
; attr on the stack (3,s). The font starts at ' ' (tile 0). 33 cycles a
; character; Calypsi's loop took about 110 with the call.
print:        asl     a
              tax                               ; X = byte offset
              lda     3,s
              xba
              and     ##0xFF00
              sec
              sbc     ##0x0020
              sta     dp:.tiny (pr_base)
              ldy     ##0
print_l:      lda     (dp:.tiny _Dp),y          ; this character (and the next)
              and     ##0x00FF
              beq     print_done
              clc
              adc     dp:.tiny (pr_base)
              sta     bg3map,x
              inx
              inx
              iny
              bra     print_l
print_done:   sep     #0x20
              lda     #1
              sta     dp:.tiny (bg3_dirty)
              rep     #0x20
              txa
              lsr     a
              rts

; void field_clear_trail(uint16_t n): the first n trail cells := C_OPEN, each
; re-tiled in the BG1 shadow (legacy wipe_trail's loop)
field_clear_trail: asl    a
              sta     dp:.tiny (ct_end)
              lda     ##0
field_clear_trail_l: cmp  dp:.tiny (ct_end)
              bcs     field_clear_trail_done
              sta     dp:.tiny (ct_i)
              tax
              lda     long:trail,x
              tax
              sep     #0x20
              stz     grid,x
              jsr     update_cell               ; A8 in and out
              rep     #0x20
              lda     dp:.tiny (ct_i)
              inc     a
              inc     a
              bra     field_clear_trail_l
field_clear_trail_done: rep #0x30
              rts

; void bg3_clear(uint16_t at, uint16_t n): n BG3 shadow cells from `at` := 0
; (marks BG3 dirty). Calypsi passes a second 16-bit argument in the _Dp
; pseudo-register. 15 cycles a cell; Calypsi's own loop took 45.
              .extern _Dp
bg3_clear:    asl     a
              tax                               ; X = byte offset
              ldy     dp:.tiny _Dp              ; Y = cells
              beq     bg3_clear_done
bg3_clear_l:  stz     bg3map,x
              inx
              inx
              dey
              bne     bg3_clear_l
bg3_clear_done: sep   #0x20
              lda     #1
              sta     dp:.tiny (bg3_dirty)
              rep     #0x20
              rts

spc_init:     sep     #0x20
              jsr     spc_init_k
              rep     #0x30
              rts

; void apu_write(uint16_t reg_val): DSP register (high byte) := value (low)
apu_write:    sep     #0x20
              sta     dp:.tiny (apu_val)
              xba
              sta     dp:.tiny (apu_reg)
              jsr     apu_write_k
              rep     #0x30
              rts

; =============================================================================
;  Boot: Calypsi's startup calls __low_level_init before it initialises C
;  data. We clear all 128KB of WRAM here, except the return address we pop
;  and push back, so C starts from a known state.
; =============================================================================
              .public __low_level_init
__low_level_init:
              sep     #0x20
              lda     #0x80
              sta     INIDISP
              stz     NMITIMEN
              stz     MDMAEN
              stz     HDMAEN
              rep     #0x30
              plx                             ; return address
              sep     #0x20
              stz     WMADDL
              stz     WMADDM
              stz     WMADDH
              lda     #0x08                   ; fixed source, one register
              sta     DMAP0
              lda     #0x80                   ; $2180 WMDATA
              sta     BBAD0
              ldy     ##.word0 zero_byte
              sty     A1T0L
              lda     #.byte2 zero_byte
              sta     A1B0
              ldy     ##0
              sty     DAS0L                   ; 0 = 65536 bytes
              lda     #1
              sta     MDMAEN
              ldy     ##0
              sty     DAS0L
              sta     MDMAEN                  ; and the second 64KB
              rep     #0x30
              phx
              rts

              .section nmivec, root
              .word   nmi
              .section irqvec, root
              .word   irq_stub
              .section code
irq_stub:     rti

; =============================================================================
;  Data the kernels read with absolute addressing (bank 0)
; =============================================================================
              .section cnear,rodata
zero_byte:    .byte   0
bit_tab:      .byte   1, 2, 4, 8, 16, 0, 0, 0
seed_offs:    .word   0xFFFF, 1, 0xFFC0, 64, 0xFFFE, 2, 0xFF80, 128, 0xFFBF, 0xFFC1, 63, 65
seed_offs_end:
trail_cols:
              .word   0x177f, 0x47ff, 0x7fff, 0x47ff
              .word   0x177f, 0x0a5f, 0x017f, 0x0a5f
bg3_pal:
              .word   0x0000, 0x7fff, 0x1442, 0x7f34
              .word   0x0000, 0x2b9f, 0x0045, 0x163f
              .word   0x0000, 0x7ea5, 0x1421, 0x7ffc
              .word   0x0000, 0x4bf0, 0x0060, 0x67f9
              .word   0x0000, 0x723f, 0x0c05, 0x7b3f
              .word   0x0000, 0x165f, 0x0046, 0x3f7f
bg1_pal:
              .word   0x0000, 0x1841, 0x4106, 0x7fda
              .word   0x177f, 0x660b, 0, 0
              .word   0, 0, 0, 0, 0, 0, 0, 0
card_pals:
              .word   0, 0x00a8, 0x0db4, 0x379f, 0x177f, 0x165a, 0, 0
              .word   0, 0, 0, 0, 0, 0, 0, 0
              .word   0, 0x1841, 0x4106, 0x4bf0, 0x177f, 0x2ea7, 0, 0
              .word   0, 0, 0, 0, 0, 0, 0, 0
              .word   0, 0x1841, 0x4106, 0x721f, 0x177f, 0x54f7, 0, 0
              .word   0, 0, 0, 0, 0, 0, 0, 0
spc_blob:
              .byte 0x20   ; clrp
              .byte 0xCD, 0xEF   ; mov x,#$ef
              .byte 0xBD   ; mov sp,x
              .byte 0xE4, 0xF4   ; mov a,$f4
              .byte 0xC4, 0x00   ; mov $00,a      last := port0
              .byte 0x8F, 0xA5, 0xF5   ; mov $f5,#$a5   READY (after last!)
              .byte 0xE4, 0xF4   ; loop: mov a,$f4
              .byte 0x64, 0x00   ; cmp a,$00
              .byte 0xF0, 0xFA   ; beq loop
              .byte 0xC4, 0x00   ; mov $00,a
              .byte 0xE4, 0xF5   ; mov a,$f5
              .byte 0xC4, 0xF2   ; mov $f2,a
              .byte 0xE4, 0xF6   ; mov a,$f6
              .byte 0xC4, 0xF3   ; mov $f3,a
              .byte 0xE4, 0x00   ; mov a,$00
              .byte 0xC4, 0xF4   ; mov $f4,a
              .byte 0x2F, 0xEA   ; bra loop
              .space 0x0300 - 0x0200 - 33, 0
              .word 0x0400, 0x0400, 0x0410, 0x0410
              .space 0x0400 - 0x0308, 0
              .byte 0xB3, 0x77, 0x77, 0x77, 0x77, 0x99, 0x99, 0x99, 0x99
              .space 7, 0
              .byte 0xB0, 0x01, 0x23, 0x45, 0x67, 0x76, 0x54, 0x32, 0x10
              .byte 0xB3, 0xFE, 0xDC, 0xBA, 0x98, 0x89, 0xAB, 0xCD, 0xEF
spc_blob_end:
pic_chr_lo:   .word   .word0 pic0_chr, .word0 pic1_chr, .word0 pic2_chr, .word0 pic3_chr
pic_bank:     .word   .word2 pic0_chr, .word2 pic1_chr, .word2 pic2_chr, .word2 pic3_chr
pic_chr_len:  .word   pic0_chr_end-pic0_chr, pic1_chr_end-pic1_chr, pic2_chr_end-pic2_chr, pic3_chr_end-pic3_chr
pic_map_lo:   .word   .word0 pic0_map, .word0 pic1_map, .word0 pic2_map, .word0 pic3_map
pic_pal_lo:   .word   .word0 pic0_pal, .word0 pic1_pal, .word0 pic2_pal, .word0 pic3_pal

; =============================================================================
;  Assets (far ROM, DMA only)
; =============================================================================
              .section cfar,rodata
              .public title_map
pic0_chr:     .incbin "pic0.chr"
pic0_chr_end:
pic0_map:     .incbin "pic0.map"
pic0_pal:     .incbin "pic0.pal"
              .section cfar,rodata
pic1_chr:     .incbin "pic1.chr"
pic1_chr_end:
pic1_map:     .incbin "pic1.map"
pic1_pal:     .incbin "pic1.pal"
              .section cfar,rodata
pic2_chr:     .incbin "pic2.chr"
pic2_chr_end:
pic2_map:     .incbin "pic2.map"
pic2_pal:     .incbin "pic2.pal"
              .section cfar,rodata
pic3_chr:     .incbin "pic3.chr"
pic3_chr_end:
pic3_map:     .incbin "pic3.map"
pic3_pal:     .incbin "pic3.pal"
              .section cfar,rodata
bg_tiles:     .incbin "bgtiles.bin"
font_tiles:   .incbin "font.bin"
font_end:
obj_tiles:    .incbin "sprites.bin"
obj_pal:      .incbin "objpal.bin"
icon_tiles:   .incbin "icons.bin"
icon_pal:     .incbin "iconpal.bin"
mini_tiles:   .incbin "minis.bin"
title_map:    .incbin "title.map"
