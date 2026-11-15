; =============================================================================
;  NOLFIED - a territory-claiming arcade game for the Super Nintendo / Super
;  Famicom. Cut lines through the force field to claim area and reveal the
;  hidden picture underneath. Enclose 80% of the field to clear a stage.
;
;  65816 assembly for ca65/ld65. LoROM, 256KB, no coprocessor.
; =============================================================================
.p816
.smart +

.define RGB(r,g,b) ((((b)>>3)<<10)|(((g)>>3)<<5)|((r)>>3))

; ---- PPU / CPU registers -----------------------------------------------------
INIDISP  = $2100
OBSEL    = $2101
OAMADDL  = $2102
OAMADDH  = $2103
BGMODE   = $2105
BG1SC    = $2107
BG2SC    = $2108
BG3SC    = $2109
BG12NBA  = $210B
BG34NBA  = $210C
BG1HOFS  = $210D
BG1VOFS  = $210E
BG2HOFS  = $210F
BG2VOFS  = $2110
BG3HOFS  = $2111
BG3VOFS  = $2112
VMAIN    = $2115
VMADDL   = $2116
CGADD    = $2121
CGDATA   = $2122
TM       = $212C
APUIO0   = $2140
APUIO1   = $2141
APUIO2   = $2142
APUIO3   = $2143
WMADDL   = $2181
WMADDM   = $2182
WMADDH   = $2183
NMITIMEN = $4200
WRDIVL   = $4204
WRDIVB   = $4206
MDMAEN   = $420B
HDMAEN   = $420C
RDNMI    = $4210
HVBJOY   = $4212
RDDIVL   = $4214
RDMPYL   = $4216
JOY1L    = $4218
DMAP0    = $4300
BBAD0    = $4301
A1T0L    = $4302
A1B0     = $4304
DAS0L    = $4305

; ---- memory map --------------------------------------------------------------
OAM_BUF  = $0200            ; 512 bytes low table
OAM_HI   = $0400            ; 32 bytes high table
E_X      = $0500            ; enemies: 8 slots of words (8.8 fixed, field px)
E_Y      = $0510
E_VX     = $0520
E_VY     = $0530
E_TYPE   = $0540            ; 0 none, 1 boss, 2 minion
E_HALF   = $0550            ; half hitbox size
E_TIMER  = $0560
E_SPD    = $0570
X_X      = $0580            ; explosions: 4 slots
X_Y      = $0588
X_T      = $0590
I_X      = $05A0            ; items: 2 slots
I_Y      = $05A4
I_ON     = $05A8
GRID     = $0880            ; 48 rows x 64 (60 used), padded 2 rows each side
BG1MAP   = $7E2000          ; BG1 tilemap shadow (2KB)
BG3MAP   = $7E2800          ; BG3 tilemap shadow (2KB)
TRAIL    = $7E3000          ; list of trail cell indices
FLOOD    = $7E5000          ; flood fill stack

FIELD_W  = 60
FIELD_H  = 48
INTERIOR = 58*46

; cell states
C_OPEN   = 0
C_CLAIM  = 1
C_EDGE   = 2
C_TRAIL  = 3
F_OPEN   = 1
F_CLAIM  = 2
F_EDGE   = 4
F_TRAIL  = 8

; game states
ST_TITLE = 0
ST_READY = 1
ST_PLAY  = 2
ST_DYING = 3
ST_CLEAR = 4
ST_OVER  = 5

PM_EDGE    = 0
PM_DRAW    = 1
PM_RETRACT = 2

BTN_START = $1000
BTN_CUT   = $C0C0           ; B, Y, A or X

ATTR_W = $20                ; BG3 text: priority, palette 0 (white)
ATTR_Y = $24                ; palette 1 (yellow)

.macro A8
        sep #$20
.endmacro
.macro A16
        rep #$20
.endmacro

.macro VRAM_LOAD src, vaddr, len
        ldx #.loword(src)
        stx dma_src
        lda #^src
        sta dma_src+2
        ldx #len
        stx dma_len
        ldx #vaddr
        jsr dma_to_vram
.endmacro

.macro CGRAM_LOAD src, cidx, len
        ldx #.loword(src)
        stx dma_src
        lda #^src
        sta dma_src+2
        ldx #len
        stx dma_len
        lda #cidx
        jsr dma_to_cgram
.endmacro

.macro PRINT row, col, str, attr
        ldx #.loword(str)
        stx str_ptr
        lda #attr
        sta text_attr
        ldx #((row)*64 + (col)*2)
        jsr print
.endmacro

.macro DSPW reg, val
        lda #reg
        sta apu_reg
        lda #val
        sta apu_val
        jsr apu_write
.endmacro

.macro SFX ch, data
        phx
        phy
        ldy #((ch)*2)
        ldx #.loword(data)
        jsr sfx_start
        ply
        plx
.endmacro

; =============================================================================
.segment "ZEROPAGE"
nmi_count:   .res 1
frame_ready: .res 1
bg1_dirty:   .res 1
bg3_dirty:   .res 1
tm_val:      .res 1
bright:      .res 1
state:       .res 1
paused:      .res 1
joy:         .res 2
joy_prev:    .res 2
joy_new:     .res 2
rng:         .res 2
rtmp:        .res 2
rv_r:        .res 2
timer:       .res 2
tmp0:        .res 2
tmp1:        .res 2
tmp2:        .res 2
tmp3:        .res 2
t_x:         .res 2
t_y:         .res 2
ut_tmp:      .res 2
ec_tmp:      .res 2
dma_src:     .res 3
dma_len:     .res 2
str_ptr:     .res 2
text_attr:   .res 1
bx0:         .res 1
bx1:         .res 1
by0:         .res 1
by1:         .res 1
cx0:         .res 1
cx1:         .res 1
cy0:         .res 1
cy1:         .res 1
ccx:         .res 1
bflags:      .res 1
bs_tmp:      .res 2
p_idx:       .res 2
start_idx:   .res 2
trail_len:   .res 2
pmode:       .res 1
pmove_timer: .res 1
pspeed:      .res 1
ppx:         .res 1
ppy:         .res 1
invuln:      .res 2
shield:      .res 2
freeze:      .res 2
lives:       .res 1
stage:       .res 1
score:       .res 4         ; BCD, in units of 10 points
hiscore:     .res 4
claimed:     .res 2
pct:         .res 1
newly:       .res 2
noseed:      .res 1
enx:         .res 2
eslot:       .res 2
msg_timer:   .res 2
loopi:       .res 2
bcd_out:     .res 2
bonus:       .res 2
s_cx:        .res 2
s_cy:        .res 2
s_r:         .res 2
s_dx:        .res 2
s_dy:        .res 2
s_row:       .res 2
boom_x:      .res 1
boom_y:      .res 1
spr_x:       .res 2
spr_y:       .res 1
spr_tile:    .res 1
spr_attr:    .res 1
spr_big:     .res 1
spr_slot:    .res 2
ps_bits:     .res 1
apu_cnt:     .res 1
apu_reg:     .res 1
apu_val:     .res 1
ch_ptr:      .res 8
ch_timer:    .res 8
ch_new:      .res 8
sptr:        .res 2
sfx_ch:      .res 2

; =============================================================================
.segment "CODE"

.proc reset
        .a8
        .i16
        sei
        clc
        xce
        rep #$38
        ldx #$1FFF
        txs
        lda #$0000
        tcd
        sep #$20
        lda #$80
        sta INIDISP
        stz NMITIMEN
        stz MDMAEN
        stz HDMAEN
        lda #$00
        pha
        plb
        ; clear all 128KB of WRAM with a fixed-source DMA
        stz WMADDL
        stz WMADDM
        stz WMADDH
        lda #$08
        sta DMAP0
        lda #$80
        sta BBAD0
        ldx #.loword(zero_byte)
        stx A1T0L
        lda #^zero_byte
        sta A1B0
        ldx #$0000
        stx DAS0L
        lda #$01
        sta MDMAEN
        ldx #$0000
        stx DAS0L
        sta MDMAEN

        jsr init_ppu
        jsr spc_init
        jsr load_static
        jsr init_oam
        A16
        lda #$ACE1
        sta rng
        A8
        jsr enter_title

main_loop:
        jsr wait_nmi
        jsr read_joy
        jsr sfx_update
        A16
        lda state
        and #$00FF
        asl
        tax
        A8
        jsr (state_tab,x)
        jsr build_oam
        lda #$01
        sta frame_ready
        bra main_loop
.endproc

state_tab:
        .word st_title, st_ready, st_play, st_dying, st_clear, st_over

.proc irq_stub
        .a8
        .i16
        rti
.endproc

; -----------------------------------------------------------------------------
.proc nmi
        .a8
        .i16
        rep #$30
        pha
        phx
        phy
        phb
        phd
        pea $0000
        pld
        sep #$20
        lda #$00
        pha
        plb
        lda RDNMI
        lda frame_ready
        bne :+
        jmp done
:
        ; OAM
        stz OAMADDL
        stz OAMADDH
        stz DMAP0
        lda #$04
        sta BBAD0
        ldx #OAM_BUF
        stx A1T0L
        stz A1B0
        ldx #544
        stx DAS0L
        lda #$01
        sta MDMAEN
        ; BG1 field rows 3..26
        lda bg1_dirty
        beq nobg1
        lda #$80
        sta VMAIN
        ldx #($7000 + 3*32)
        stx VMADDL
        lda #$01
        sta DMAP0
        lda #$18
        sta BBAD0
        ldx #.loword(BG1MAP + 3*64)
        stx A1T0L
        lda #^BG1MAP
        sta A1B0
        ldx #(24*64)
        stx DAS0L
        lda #$01
        sta MDMAEN
        stz bg1_dirty
nobg1:
        lda bg3_dirty
        beq nobg3
        lda #$80
        sta VMAIN
        ldx #$7800
        stx VMADDL
        lda #$01
        sta DMAP0
        lda #$18
        sta BBAD0
        ldx #.loword(BG3MAP)
        stx A1T0L
        lda #^BG3MAP
        sta A1B0
        ldx #(28*64)
        stx DAS0L
        lda #$01
        sta MDMAEN
        stz bg3_dirty
nobg3:
        ; cycle the trail colour (CGRAM 36)
        lda #36
        sta CGADD
        A16
        lda nmi_count
        lsr
        and #$000E
        tax
        A8
        lda trail_cols,x
        sta CGDATA
        lda trail_cols+1,x
        sta CGDATA
        lda tm_val
        sta TM
        lda bright
        sta INIDISP
        stz frame_ready
done:
        inc nmi_count
        rep #$30
        pld
        plb
        ply
        plx
        pla
        rti
.endproc

; -----------------------------------------------------------------------------
.proc init_ppu
        .a8
        .i16
        lda #$80
        sta INIDISP
        ldx #$2101
@a:     stz $0000,x
        inx
        cpx #$210D
        bne @a
@b:     stz $0000,x             ; scroll regs: write twice
        stz $0000,x
        inx
        cpx #$2115
        bne @b
        lda #$80
        sta VMAIN
        stz $2116
        stz $2117
        stz $211A
        stz $211B
        lda #$01
        sta $211B
        stz $211C
        stz $211C
        stz $211D
        stz $211D
        stz $211E
        sta $211E
        stz $211F
        stz $211F
        stz $2120
        stz $2120
        stz $2121
        ldx #$2123
@c:     stz $0000,x
        inx
        cpx #$2134
        bne @c
        lda #$FF
        sta $4201
        ldx #$4202
@d:     stz $0000,x
        inx
        cpx #$420E
        bne @d
        rts
.endproc

.proc wait_nmi
        .a8
        .i16
        lda nmi_count
@w:     cmp nmi_count
        beq @w
        rts
.endproc

.proc read_joy
        .a8
        .i16
@w:     lda HVBJOY
        and #$01
        bne @w
        A16
        lda joy
        sta joy_prev
        lda JOY1L
        sta joy
        lda joy_prev
        eor #$FFFF
        and joy
        sta joy_new
        A8
        rts
.endproc

; X = VRAM word address, dma_src/dma_len set
.proc dma_to_vram
        .a8
        .i16
        lda #$80
        sta VMAIN
        stx VMADDL
        lda #$01
        sta DMAP0
        lda #$18
        sta BBAD0
        ldx dma_src
        stx A1T0L
        lda dma_src+2
        sta A1B0
        ldx dma_len
        stx DAS0L
        lda #$01
        sta MDMAEN
        rts
.endproc

; A = first colour index
.proc dma_to_cgram
        .a8
        .i16
        sta CGADD
        stz DMAP0
        lda #$22
        sta BBAD0
        ldx dma_src
        stx A1T0L
        lda dma_src+2
        sta A1B0
        ldx dma_len
        stx DAS0L
        lda #$01
        sta MDMAEN
        rts
.endproc

.proc load_static
        .a8
        .i16
        VRAM_LOAD bg_tiles,   $0000, 8192
        VRAM_LOAD font_tiles, $4000, (font_end - font_tiles)
        VRAM_LOAD obj_tiles,  $6000, 4096
        CGRAM_LOAD bg3_pal, 0, 24
        CGRAM_LOAD bg1_pal, 32, 32
        CGRAM_LOAD obj_pal, 128, 128
        lda #$09                ; mode 1, BG3 high priority
        sta BGMODE
        lda #$70
        sta BG1SC
        lda #$74
        sta BG2SC
        lda #$78
        sta BG3SC
        lda #$10
        sta BG12NBA
        lda #$04
        sta BG34NBA
        lda #$63                ; 16x16/32x32 sprites at VRAM $6000
        sta OBSEL
        stz BG1HOFS
        stz BG1HOFS
        stz BG2HOFS
        stz BG2HOFS
        stz BG3HOFS
        stz BG3HOFS
        lda #$FF
        sta BG1VOFS
        sta BG1VOFS
        sta BG2VOFS
        sta BG2VOFS
        sta BG3VOFS
        sta BG3VOFS
        lda #$17
        sta tm_val
        sta TM
        lda #$0F
        sta bright
        rts
.endproc

.proc init_oam
        .a8
        .i16
        ldx #$0000
@l:     stz OAM_BUF,x
        lda #224
        sta OAM_BUF+1,x
        stz OAM_BUF+2,x
        stz OAM_BUF+3,x
        inx
        inx
        inx
        inx
        cpx #512
        bne @l
        ldx #$0000
@h:     stz OAM_HI,x
        inx
        cpx #32
        bne @h
        rts
.endproc

.proc upload_bg1
        .a8
        .i16
        ldx #.loword(BG1MAP)
        stx dma_src
        lda #^BG1MAP
        sta dma_src+2
        ldx #2048
        stx dma_len
        ldx #$7000
        jmp dma_to_vram
.endproc

.proc upload_bg3
        .a8
        .i16
        ldx #.loword(BG3MAP)
        stx dma_src
        lda #^BG3MAP
        sta dma_src+2
        ldx #2048
        stx dma_len
        ldx #$7800
        jmp dma_to_vram
.endproc

.proc upload_oam
        .a8
        .i16
        stz OAMADDL
        stz OAMADDH
        stz DMAP0
        lda #$04
        sta BBAD0
        ldx #OAM_BUF
        stx A1T0L
        stz A1B0
        ldx #544
        stx DAS0L
        lda #$01
        sta MDMAEN
        rts
.endproc

; A = picture number 0..3. Must be in forced blank.
.proc load_picture
        .a8
        .i16
        A16
        and #$0003
        asl
        tax
        lda pic_chr_lo,x
        sta dma_src
        lda pic_chr_len,x
        sta dma_len
        A8
        lda pic_bank,x
        sta dma_src+2
        phx
        ldx #$1000
        jsr dma_to_vram
        plx
        A16
        lda pic_map_lo,x
        sta dma_src
        lda #2048
        sta dma_len
        A8
        phx
        ldx #$7400
        jsr dma_to_vram
        plx
        A16
        lda pic_pal_lo,x
        sta dma_src
        lda #32
        sta dma_len
        A8
        lda #48
        jmp dma_to_cgram
.endproc

; -----------------------------------------------------------------------------
; Random numbers (xorshift16). A16 in/out.
.proc rand16
        .a8
        .i16
        .a16
        lda rng
        sta rtmp
        asl
        asl
        asl
        asl
        asl
        asl
        asl
        eor rtmp
        sta rtmp
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        eor rtmp
        sta rtmp
        xba
        and #$FF00
        eor rtmp
        sta rng
        rts
.endproc

.proc rand8
        .a8
        .i16
        A16
        jsr rand16
        A8
        rts
.endproc

; -----------------------------------------------------------------------------
;  Text
; -----------------------------------------------------------------------------
; str_ptr = string (bank 0), X = map byte offset, text_attr
.proc print
        .a8
        .i16
        ldy #$0000
@l:     lda (str_ptr),y
        beq @d
        sec
        sbc #32
        sta f:BG3MAP,x
        lda text_attr
        sta f:BG3MAP+1,x
        inx
        inx
        iny
        bra @l
@d:     lda #$01
        sta bg3_dirty
        rts
.endproc

; A = digit 0..9, X = map offset (advanced by 2)
.proc put_digit
        .a8
        .i16
        and #$0F
        clc
        adc #16
        sta f:BG3MAP,x
        lda text_attr
        sta f:BG3MAP+1,x
        inx
        inx
        rts
.endproc

; A = BCD byte
.proc put_bcd
        .a8
        .i16
        pha
        lsr
        lsr
        lsr
        lsr
        jsr put_digit
        pla
        jmp put_digit
.endproc

; A = row
.proc clear_row
        .a8
        .i16
        A16
        and #$00FF
        asl
        asl
        asl
        asl
        asl
        asl
        tax
        ldy #32
        lda #$0000
@l:     sta f:BG3MAP,x
        inx
        inx
        dey
        bne @l
        A8
        lda #$01
        sta bg3_dirty
        rts
.endproc

.proc clear_bg3
        .a8
        .i16
        A16
        ldx #$0000
        lda #$0000
@l:     sta f:BG3MAP,x
        inx
        inx
        cpx #2048
        bne @l
        A8
        lda #$01
        sta bg3_dirty
        rts
.endproc

; A = value 0..99 -> two digits at X
.proc put_dec2
        .a8
        .i16
        A16
        and #$00FF
        sta WRDIVL
        A8
        lda #10
        sta WRDIVB
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        lda RDDIVL
        jsr put_digit
        lda RDMPYL
        jmp put_digit
.endproc

.proc draw_hud
        .a8
        .i16
        PRINT 1, 1, s_score, ATTR_W
        PRINT 1, 19, s_stage, ATTR_W
        PRINT 2, 1, s_area, ATTR_W
        PRINT 2, 19, s_lives, ATTR_W
        lda #ATTR_Y
        sta text_attr
        ldx #(1*64 + 7*2)
        lda score+2
        jsr put_bcd
        lda score+1
        jsr put_bcd
        lda score
        jsr put_bcd
        lda #0
        jsr put_digit
        ldx #(1*64 + 25*2)
        lda stage
        jsr put_dec2
        ldx #(2*64 + 6*2)
        lda pct
        jsr put_dec2
        ldx #(2*64 + 25*2)
        lda #$0A                ; '*' heart is ASCII 42 -> tile 10
        sta f:BG3MAP,x
        lda #ATTR_Y
        sta f:BG3MAP+1,x
        inx
        inx
        lda lives
        jsr put_digit
        lda #$01
        sta bg3_dirty
        rts
.endproc

; str_ptr preset by caller via X = string address
.proc show_msg
        .a8
        .i16
        stx str_ptr
        lda #27
        jsr clear_row
        lda #ATTR_Y
        sta text_attr
        ldx #(27*64 + 2*2)
        jsr print
        ldx #150
        stx msg_timer
        rts
.endproc

; -----------------------------------------------------------------------------
;  Field
; -----------------------------------------------------------------------------
.proc init_field
        .a8
        .i16
        ldx #$0000
        lda #C_CLAIM
@pad:   sta $0800,x
        inx
        cpx #$0D00
        bne @pad
        ldx #$0000
@c:     A16
        txa
        and #$003F
        cmp #FIELD_W
        bcs @next
        tay
        txa
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        A8
        cmp #0
        beq @border
        cmp #(FIELD_H-1)
        beq @border
        cpy #0
        beq @border
        cpy #(FIELD_W-1)
        beq @border
        lda #C_OPEN
        bra @st
@border:
        lda #C_EDGE
@st:    sta GRID,x
@next:  A8
        inx
        cpx #(FIELD_H*64)
        bne @c
        rts
.endproc

; tile at (t_x, t_y) in tile units -> BG1 shadow
.proc update_tile_txy
        .a8
        .i16
        A16
        lda t_y
        and #$00FF
        xba
        lsr
        sta ut_tmp
        lda t_x
        and #$00FF
        asl
        clc
        adc ut_tmp
        tax                     ; X = top-left cell
        lda t_y
        and #$00FF
        asl
        asl
        asl
        asl
        asl
        asl
        sta ut_tmp
        lda t_x
        and #$00FF
        asl
        clc
        adc ut_tmp
        adc #(3*64 + 2)
        tay                     ; Y = map offset
        A8
        lda GRID+65,x
        asl
        asl
        ora GRID+64,x
        asl
        asl
        ora GRID+1,x
        asl
        asl
        ora GRID,x
        sta ut_tmp
        tyx
        sta f:BG1MAP,x
        lda #$08                ; palette 2
        sta f:BG1MAP+1,x
        lda #$01
        sta bg1_dirty
        rts
.endproc

; X = cell index
.proc update_cell
        .a8
        .i16
        A16
        txa
        and #$003F
        lsr
        sta t_x
        txa
        asl
        xba
        and #$00FF
        sta t_y
        A8
        jmp update_tile_txy
.endproc

.proc redraw_all
        .a8
        .i16
        A16
        lda #(85 | $0800)       ; fully transparent tile outside the field
        ldx #$0000
@f:     sta f:BG1MAP,x
        inx
        inx
        cpx #2048
        bne @f
        stz t_y
@y:     stz t_x
@x:     A8
        jsr update_tile_txy
        A16
        inc t_x
        lda t_x
        cmp #30
        bne @x
        inc t_y
        lda t_y
        cmp #24
        bne @y
        A8
        lda #$01
        sta bg1_dirty
        rts
.endproc

; Bounding box scan. bx0..bx1, by0..by1 in field pixels (inclusive).
; Returns A = OR of (1 << state) for all cells touched. Clobbers X, Y.
.proc box_scan
        .a8
        .i16
        lda bx0
        cmp #240
        bcc :+
        lda #0
:       lsr
        lsr
        sta cx0
        lda bx1
        cmp #240
        bcc :+
        lda #239
:       lsr
        lsr
        sta cx1
        lda by0
        cmp #192
        bcc :+
        lda #0
:       lsr
        lsr
        sta cy0
        lda by1
        cmp #192
        bcc :+
        lda #191
:       lsr
        lsr
        sta cy1
        stz bflags
@row:   A16
        lda cy0
        and #$00FF
        asl
        asl
        asl
        asl
        asl
        asl
        sta bs_tmp
        lda cx0
        and #$00FF
        clc
        adc bs_tmp
        tax
        A8
        lda cx0
        sta ccx
@col:   A16
        lda GRID,x
        and #$0007
        tay
        A8
        lda bit_tab,y
        tsb bflags
        inx
        lda ccx
        cmp cx1
        bcs @rowdone
        inc ccx
        bra @col
@rowdone:
        lda cy0
        cmp cy1
        bcs @done
        inc cy0
        bra @row
@done:  lda bflags
        rts
.endproc

bit_tab: .byte 1, 2, 4, 8, 16, 0, 0, 0

; X = enemy slot -> Y = cell index of its centre
.proc enemy_cell
        .a8
        .i16
        A16
        lda E_Y,x
        xba
        and #$00FF
        lsr
        lsr
        asl
        asl
        asl
        asl
        asl
        asl
        sta ec_tmp
        lda E_X,x
        xba
        and #$00FF
        lsr
        lsr
        clc
        adc ec_tmp
        tay
        A8
        rts
.endproc

; X = item slot -> Y = cell index
.proc item_cell
        .a8
        .i16
        A16
        lda I_Y,x
        and #$00FF
        lsr
        lsr
        asl
        asl
        asl
        asl
        asl
        asl
        sta ec_tmp
        lda I_X,x
        and #$00FF
        lsr
        lsr
        clc
        adc ec_tmp
        tay
        A8
        rts
.endproc

seed_offs:
        .word $FFFF, 1, $FFC0, 64, $FFFE, 2, $FF80, 128, $FFBF, $FFC1, 63, 65
seed_offs_end:

; Close the current trail: claim everything not reachable from the boss.
.proc do_fill
        .a8
        .i16
        stz noseed
        ldx #$0000
        jsr enemy_cell
        sty tmp2
        lda GRID,y
        beq @seed
        ldx #$0000
@try:   A16
        lda tmp2
        clc
        adc seed_offs,x
        tay
        A8
        lda GRID,y
        beq @seed
        inx
        inx
        cpx #(seed_offs_end - seed_offs)
        bne @try
        lda #$01
        sta noseed
        jmp @pass
@seed:  lda #4
        sta GRID,y
        A16
        tya
        sta f:FLOOD
        ldx #$0002
@pop:   A16
        cpx #$0000
        beq @fdone
        dex
        dex
        lda f:FLOOD,x
        tay
        A8
        lda GRID-1,y
        bne @n1
        lda #4
        sta GRID-1,y
        A16
        tya
        dec a
        sta f:FLOOD,x
        inx
        inx
        A8
@n1:    lda GRID+1,y
        bne @n2
        lda #4
        sta GRID+1,y
        A16
        tya
        inc a
        sta f:FLOOD,x
        inx
        inx
        A8
@n2:    lda GRID-64,y
        bne @n3
        lda #4
        sta GRID-64,y
        A16
        tya
        sec
        sbc #64
        sta f:FLOOD,x
        inx
        inx
        A8
@n3:    lda GRID+64,y
        bne @pop
        lda #4
        sta GRID+64,y
        A16
        tya
        clc
        adc #64
        sta f:FLOOD,x
        inx
        inx
        bra @pop
@fdone: A8

@pass:  ; convert: open (unreached) & trail -> claimed, reached -> open
        A8
        ldx #$0000
        stx newly
@p:     lda GRID,x
        beq @zero
        cmp #C_TRAIL
        beq @claim
        cmp #4
        bne @pn
        stz GRID,x
        bra @pn
@zero:  lda noseed
        bne @pn
@claim: lda #C_CLAIM
        sta GRID,x
        A16
        inc newly
        A8
@pn:    inx
        cpx #(FIELD_H*64)
        bne @p

        ; recompute edges: claimed cell touching an open cell (8-way)
        ldx #$0000
@e:     lda GRID,x
        beq @en
        lda GRID-65,x
        beq @edge
        lda GRID-64,x
        beq @edge
        lda GRID-63,x
        beq @edge
        lda GRID-1,x
        beq @edge
        lda GRID+1,x
        beq @edge
        lda GRID+63,x
        beq @edge
        lda GRID+64,x
        beq @edge
        lda GRID+65,x
        beq @edge
        lda #C_CLAIM
        sta GRID,x
        bra @en
@edge:  lda #C_EDGE
        sta GRID,x
@en:    inx
        cpx #(FIELD_H*64)
        bne @e

        ; percentage = claimed * 100 / 2668 ~= claimed * 3 / 80
        A16
        lda claimed
        clc
        adc newly
        sta claimed
        sta tmp0
        asl
        clc
        adc tmp0
        sta WRDIVL
        A8
        lda #80
        sta WRDIVB
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        lda RDDIVL
        cmp #100
        bcc :+
        lda #99
:       sta pct
        A16
        lda newly
        jsr bin2bcd
        jsr add_score
        A8
        jsr redraw_all
        jsr check_enclosed
        jsr snap_player
        jsr draw_hud
        lda pct
        cmp #80
        bcc @nc
        jmp enter_clear
@nc:    SFX 0, sfx_claim
        rts
.endproc

; A16 binary (< 10000) -> A16 BCD
.proc bin2bcd
        .a8
        .i16
        .a16
        sta WRDIVL
        A8
        lda #10
        sta WRDIVB
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        A16
        lda RDMPYL
        sta bcd_out
        lda RDDIVL
        sta WRDIVL
        A8
        lda #10
        sta WRDIVB
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        A16
        lda RDMPYL
        asl
        asl
        asl
        asl
        tsb bcd_out
        lda RDDIVL
        sta WRDIVL
        A8
        lda #10
        sta WRDIVB
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        A16
        lda RDMPYL
        xba
        tsb bcd_out
        lda RDDIVL
        xba
        asl
        asl
        asl
        asl
        tsb bcd_out
        lda bcd_out
        rts
.endproc

; A16 = BCD amount (units of 10 points)
.proc add_score
        .a8
        .i16
        .a16
        sed
        clc
        adc score
        sta score
        lda score+2
        adc #$0000
        sta score+2
        cld
        rts
.endproc

; After a fill: destroy enclosed minions, collect enclosed items
.proc check_enclosed
        .a8
        .i16
        ldx #$0002
@l:     stx eslot
        lda E_TYPE,x
        cmp #2
        bne @n
        jsr enemy_cell
        lda GRID,y
        beq @n
        stz E_TYPE,x
        lda E_X+1,x
        sta boom_x
        lda E_Y+1,x
        sta boom_y
        jsr spawn_boom
        A16
        lda #$0050
        jsr add_score
        A8
        SFX 1, sfx_kill
@n:     ldx eslot
        inx
        inx
        cpx #16
        bne @l
        ldx #$0000
@i:     stx eslot
        lda I_ON,x
        beq @in
        jsr item_cell
        lda GRID,y
        beq @in
        stz I_ON,x
        jsr collect_item
@in:    ldx eslot
        inx
        inx
        cpx #4
        bne @i
        rts
.endproc

.proc collect_item
        .a8
        .i16
        A16
        lda #$0100
        jsr add_score
        A8
        SFX 0, sfx_item
        jsr rand8
        and #$03
        beq @speed
        cmp #1
        beq @shield
        cmp #2
        beq @freeze
        lda lives
        cmp #9
        bcs :+
        inc lives
:       ldx #.loword(s_1up)
        jmp show_msg
@speed: lda #1
        sta pspeed
        ldx #.loword(s_speed)
        jmp show_msg
@shield:
        ldx #600
        stx shield
        ldx #.loword(s_shield)
        jmp show_msg
@freeze:
        ldx #300
        stx freeze
        ldx #.loword(s_freeze)
        jmp show_msg
.endproc

; make sure the player stands on an edge cell after a fill
.proc snap_player
        .a8
        .i16
        ldx p_idx
        lda GRID,x
        cmp #C_EDGE
        bne :+
        rts
:       A16
        txa
        and #$003F
        sta s_cx
        txa
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        sta s_cy
        lda #1
        sta s_r
@r:     A16
        lda #0
        sec
        sbc s_r
        sta s_dy
@dy:    A16
        lda s_cy
        clc
        adc s_dy
        bmi @ndy
        cmp #FIELD_H
        bcs @ndy
        asl
        asl
        asl
        asl
        asl
        asl
        sta s_row
        lda #0
        sec
        sbc s_r
        sta s_dx
@dx:    A16
        lda s_cx
        clc
        adc s_dx
        bmi @ndx
        cmp #FIELD_W
        bcs @ndx
        clc
        adc s_row
        tax
        A8
        lda GRID,x
        cmp #C_EDGE
        A16
        bne @ndx
        stx p_idx
        A8
        rts
@ndx:   A16
        inc s_dx
        lda s_r
        sec
        sbc s_dx
        bpl @dx
@ndy:   A16
        inc s_dy
        lda s_r
        sec
        sbc s_dy
        bpl @dy
        inc s_r
        lda s_r
        cmp #24
        bcc @r
        A8
        rts
.endproc

; -----------------------------------------------------------------------------
;  Player
; -----------------------------------------------------------------------------
dir_didx: .word $FFC0, 64, $FFFF, 1     ; up, down, left, right

.proc player_update
        .a8
        .i16
        A16
        lda joy
        and #BTN_CUT
        sta tmp0
        A8
        lda pmode
        cmp #PM_RETRACT
        bne @notret
        lda tmp0
        ora tmp0+1
        beq @doret
        lda #PM_DRAW
        sta pmode
        bra @move
@doret: jsr retract_step
        jsr retract_step
        rts
@notret:
        cmp #PM_DRAW
        bne @move
        lda tmp0
        ora tmp0+1
        bne @move
        lda #PM_RETRACT
        sta pmode
        rts
@move:  dec pmove_timer
        beq :+
        rts
:       lda pspeed
        sta pmove_timer
        lda joy+1
        sta tmp1
        bit #$08
        beq @nu
        ldy #0
        jsr try_move
        bcs @moved
@nu:    lda tmp1
        bit #$04
        beq @nd
        ldy #2
        jsr try_move
        bcs @moved
@nd:    lda tmp1
        bit #$02
        beq @nl
        ldy #4
        jsr try_move
        bcs @moved
@nl:    lda tmp1
        bit #$01
        beq @nr
        ldy #6
        jsr try_move
        bcs @moved
@nr:    lda #1
        sta pmove_timer
@moved: rts
.endproc

; Y = direction*2. Returns carry set if the player moved.
.proc try_move
        .a8
        .i16
        A16
        lda p_idx
        clc
        adc dir_didx,y
        sta tmp2
        tax
        A8
        lda GRID,x
        sta tmp3
        lda pmode
        bne @drawing
        lda tmp3
        cmp #C_EDGE
        bne @e1
        ldx tmp2
        stx p_idx
        sec
        rts
@e1:    cmp #C_OPEN
        bne @fail
        lda tmp0
        ora tmp0+1
        beq @fail
        ldx p_idx
        stx start_idx
        ldx #$0000
        stx trail_len
        lda #PM_DRAW
        sta pmode
        SFX 0, sfx_cut
        bra @add
@drawing:
        lda tmp3
        beq @add
        cmp #C_EDGE
        bne @fail
        ldx tmp2
        stx p_idx
        lda #PM_EDGE
        sta pmode
        jsr calc_ppos
        jsr do_fill
        ldx #$0000
        stx trail_len
        sec
        rts
@add:   ldx tmp2
        lda #C_TRAIL
        sta GRID,x
        stx p_idx
        A16
        lda trail_len
        asl
        tax
        lda tmp2
        sta f:TRAIL,x
        inc trail_len
        A8
        ldx tmp2
        jsr update_cell
        sec
        rts
@fail:  clc
        rts
.endproc

.proc retract_step
        .a8
        .i16
        A16
        lda trail_len
        bne @pop
        lda start_idx
        sta p_idx
        A8
        lda #PM_EDGE
        sta pmode
        rts
@pop:   A16
        dec a
        sta trail_len
        asl
        tax
        lda f:TRAIL,x
        tay
        lda trail_len
        beq @st
        dex
        dex
        lda f:TRAIL,x
        bra @set
@st:    lda start_idx
@set:   sta p_idx
        tyx
        A8
        stz GRID,x
        jmp update_cell
.endproc

.proc calc_ppos
        .a8
        .i16
        A16
        lda p_idx
        and #$003F
        asl
        asl
        ora #2
        A8
        sta ppx
        A16
        lda p_idx
        lsr
        lsr
        lsr
        lsr
        and #$FFFC
        ora #2
        A8
        sta ppy
        rts
.endproc

.proc player_hit
        .a8
        .i16
        lda state
        cmp #ST_PLAY
        bne @no
        A16
        lda invuln
        ora shield
        A8
        bne @no
        lda #ST_DYING
        sta state
        ldx #90
        stx timer
        lda ppx
        sta boom_x
        lda ppy
        sta boom_y
        jsr spawn_boom
        jsr music_stop
        SFX 1, sfx_death
@no:    rts
.endproc

; -----------------------------------------------------------------------------
;  Enemies
; -----------------------------------------------------------------------------
; X = slot: random direction with speed E_SPD
.proc randomize_vel
        .a8
        .i16
        A16
        jsr rand16
        sta rv_r
        and #$003F
        eor #$FFFF
        sec
        adc E_SPD,x
        bit rv_r
        bpl :+
        eor #$FFFF
        inc a
:       sta E_VX,x
        lda rv_r
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        and #$003F
        eor #$FFFF
        sec
        adc E_SPD,x
        bit rv_r
        bvc :+
        eor #$FFFF
        inc a
:       sta E_VY,x
        A8
        rts
.endproc

.proc init_entities
        .a8
        .i16
        ldx #$0000
@c:     stz $0500,x
        inx
        cpx #$0100
        bne @c
        ldx #(47*64 + 30)
        stx p_idx
        stz pmode
        lda #2
        sta pspeed
        lda #1
        sta pmove_timer
        ldx #$0000
        stx trail_len
        stx shield
        stx freeze
        stx msg_timer
        ldx #90
        stx invuln
        ; boss
        lda #1
        sta E_TYPE
        stz E_X
        lda #120
        sta E_X+1
        stz E_Y
        lda #80
        sta E_Y+1
        lda #11
        sta E_HALF
        A16
        lda stage
        and #$00FF
        asl
        asl
        asl
        sta tmp0
        asl
        clc
        adc tmp0
        adc #$00A8
        cmp #$0200
        bcc :+
        lda #$0200
:       sta E_SPD
        A8
        lda #60
        sta E_TIMER
        ldx #$0000
        jsr randomize_vel
        ; minions
        lda stage
        inc a
        cmp #8
        bcc :+
        lda #7
:       sta tmp3
        ldx #$0002
@m:     lda #2
        sta E_TYPE,x
        lda #4
        sta E_HALF,x
        jsr rand8
        and #$7F
        clc
        adc #56
        sta E_X+1,x
        jsr rand8
        and #$7F
        clc
        adc #24
        sta E_Y+1,x
        A16
        lda stage
        and #$00FF
        asl
        asl
        sta tmp0
        asl
        asl
        clc
        adc tmp0                ; stage * 20
        adc #$00F0
        cmp #$0240
        bcc :+
        lda #$0240
:       sta E_SPD,x
        A8
        jsr randomize_vel
        inx
        inx
        dec tmp3
        bne @m
        ; items
        ldx #$0000
@it:    lda #1
        sta I_ON,x
        jsr rand8
        and #$1F
        clc
        adc #14
        asl
        asl
        ora #2
        sta I_X,x
        jsr rand8
        and #$1F
        clc
        adc #6
        asl
        asl
        ora #2
        sta I_Y,x
        inx
        inx
        cpx #4
        bne @it
        rts
.endproc

.proc enemies_update
        .a8
        .i16
        ldx #$0000
@loop:  stx eslot
        lda E_TYPE,x
        beq @next
        lda freeze
        ora freeze+1
        bne @collide
        jsr enemy_move
        ldx eslot
        lda E_TYPE,x
        cmp #1
        bne @collide
        dec E_TIMER,x
        bne @collide
        jsr rand8
        and #$3F
        clc
        adc #50
        sta E_TIMER,x
        jsr randomize_vel
@collide:
        ldx eslot
        jsr enemy_collide
@next:  ldx eslot
        inx
        inx
        cpx #16
        bne @loop
        rts
.endproc

.proc enemy_move
        .a8
        .i16
        ; ---- horizontal
        A16
        lda E_X,x
        clc
        adc E_VX,x
        sta enx
        A8
        lda E_VX+1,x
        bmi @lft
        lda enx+1
        clc
        adc E_HALF,x
        bra @sx
@lft:   lda enx+1
        sec
        sbc E_HALF,x
@sx:    sta bx0
        sta bx1
        lda E_Y+1,x
        sec
        sbc E_HALF,x
        sta by0
        lda E_Y+1,x
        clc
        adc E_HALF,x
        sta by1
        jsr box_scan
        ldx eslot
        and #(F_CLAIM|F_EDGE)
        beq @xok
        A16
        lda #$0000
        sec
        sbc E_VX,x
        sta E_VX,x
        A8
        bra @yax
@xok:   A16
        lda enx
        sta E_X,x
        A8
@yax:   ; ---- vertical
        A16
        lda E_Y,x
        clc
        adc E_VY,x
        sta enx
        A8
        lda E_VY+1,x
        bmi @up
        lda enx+1
        clc
        adc E_HALF,x
        bra @sy
@up:    lda enx+1
        sec
        sbc E_HALF,x
@sy:    sta by0
        sta by1
        lda E_X+1,x
        sec
        sbc E_HALF,x
        sta bx0
        lda E_X+1,x
        clc
        adc E_HALF,x
        sta bx1
        jsr box_scan
        ldx eslot
        and #(F_CLAIM|F_EDGE)
        beq @yok
        A16
        lda #$0000
        sec
        sbc E_VY,x
        sta E_VY,x
        A8
        rts
@yok:   A16
        lda enx
        sta E_Y,x
        A8
        rts
.endproc

.proc enemy_collide
        .a8
        .i16
        lda E_X+1,x
        sec
        sbc E_HALF,x
        sta bx0
        lda E_X+1,x
        clc
        adc E_HALF,x
        sta bx1
        lda E_Y+1,x
        sec
        sbc E_HALF,x
        sta by0
        lda E_Y+1,x
        clc
        adc E_HALF,x
        sta by1
        jsr box_scan
        ldx eslot
        and #F_TRAIL
        beq @np
        jsr player_hit
        ldx eslot
@np:    lda pmode
        beq @done
        lda E_HALF,x
        clc
        adc #3
        sta tmp1
        lda E_X+1,x
        sec
        sbc ppx
        bcs :+
        eor #$FF
        inc a
:       cmp tmp1
        bcs @done
        lda E_Y+1,x
        sec
        sbc ppy
        bcs :+
        eor #$FF
        inc a
:       cmp tmp1
        bcs @done
        jsr player_hit
@done:  rts
.endproc

.proc spawn_boom
        .a8
        .i16
        phx
        ldx #$0000
@l:     lda X_T,x
        beq @f
        inx
        inx
        cpx #8
        bne @l
        plx
        rts
@f:     lda #24
        sta X_T,x
        lda boom_x
        sta X_X,x
        lda boom_y
        sta X_Y,x
        plx
        rts
.endproc

.proc booms_update
        .a8
        .i16
        ldx #$0000
@l:     lda X_T,x
        beq :+
        dec X_T,x
:       inx
        inx
        cpx #8
        bne @l
        rts
.endproc

.proc timers_update
        .a8
        .i16
        A16
        lda invuln
        beq :+
        dec invuln
:       lda shield
        beq :+
        dec shield
:       lda freeze
        beq :+
        dec freeze
:       lda msg_timer
        beq @done
        dec msg_timer
        bne @done
        A8
        lda #27
        jsr clear_row
@done:  A8
        rts
.endproc

; -----------------------------------------------------------------------------
;  Sprites
; -----------------------------------------------------------------------------
.proc put_sprite
        .a8
        .i16
        A16
        lda spr_slot
        asl
        asl
        tax
        A8
        lda spr_x
        sta OAM_BUF,x
        lda spr_y
        sta OAM_BUF+1,x
        lda spr_tile
        sta OAM_BUF+2,x
        lda spr_attr
        sta OAM_BUF+3,x
        A16
        lda spr_slot
        lsr
        lsr
        tax
        lda spr_slot
        and #$0003
        asl
        tay
        A8
        lda spr_x+1
        and #$01
        sta ps_bits
        lda spr_big
        beq :+
        lda ps_bits
        ora #$02
        sta ps_bits
:       cpy #0
        beq @sh
        asl ps_bits
        dey
        bra :-
@sh:    lda ps_bits
        ora OAM_HI,x
        sta OAM_HI,x
        rts
.endproc

; A = field pixel x (centre of 16x16) -> spr_x ; Y-coords similar
.proc set_small_xy
        .a8
        .i16
        ; enter with tmp0 = px, tmp1 = py (8-bit values)
        A16
        lda tmp0
        and #$00FF
        sta spr_x
        A8
        lda tmp1
        clc
        adc #15
        sta spr_y
        stz spr_big
        rts
.endproc

.proc build_oam
        .a8
        .i16
        ldx #$0000
@h:     stz OAM_BUF,x
        lda #224
        sta OAM_BUF+1,x
        inx
        inx
        inx
        inx
        cpx #64
        bne @h
        stz OAM_HI
        stz OAM_HI+1
        stz OAM_HI+2
        stz OAM_HI+3
        lda state
        cmp #ST_READY
        beq @show
        cmp #ST_PLAY
        beq @show
        cmp #ST_DYING
        beq @show
        rts
@show:
        ; ---- player (slot 0)
        lda state
        cmp #ST_DYING
        beq @noplayer
        lda invuln
        ora invuln+1
        beq :+
        lda nmi_count
        and #$02
        bne @noplayer
:       ldx #0
        stx spr_slot
        lda ppx
        sta tmp0
        lda ppy
        sta tmp1
        jsr set_small_xy
        lda nmi_count
        and #$08
        lsr
        lsr
        sta spr_tile            ; 0 or 2
        lda #$30
        sta spr_attr
        lda shield
        ora shield+1
        beq :+
        lda nmi_count
        and #$04
        beq :+
        lda #$36
        sta spr_attr
:       jsr put_sprite
@noplayer:
        ; ---- boss (slot 1)
        lda E_TYPE
        beq @noboss
        ldx #1
        stx spr_slot
        A16
        lda E_X
        xba
        and #$00FF
        sec
        sbc #8
        sta spr_x
        A8
        lda E_Y+1
        clc
        adc #7
        sta spr_y
        lda nmi_count
        and #$10
        lsr
        lsr
        clc
        adc #32
        sta spr_tile            ; 32 or 36
        lda #$32
        sta spr_attr
        lda #1
        sta spr_big
        jsr put_sprite
@noboss:
        ; ---- minions (slots 2..8)
        ldx #$0002
@m:     stx loopi
        lda E_TYPE,x
        cmp #2
        bne @mn
        lda E_X+1,x
        sta tmp0
        lda E_Y+1,x
        sta tmp1
        A16
        txa
        lsr
        inc a
        sta spr_slot
        A8
        jsr set_small_xy
        lda nmi_count
        and #$04
        lsr
        clc
        adc #4
        sta spr_tile
        lda #$34
        sta spr_attr
        jsr put_sprite
@mn:    ldx loopi
        inx
        inx
        cpx #16
        bne @m
        ; ---- items (slots 9,10)
        ldx #$0000
@i:     stx loopi
        lda I_ON,x
        beq @in
        lda I_X,x
        sta tmp0
        lda I_Y,x
        sta tmp1
        A16
        txa
        lsr
        clc
        adc #9
        sta spr_slot
        A8
        jsr set_small_xy
        lda #8
        sta spr_tile
        lda #$36
        sta spr_attr
        jsr put_sprite
@in:    ldx loopi
        inx
        inx
        cpx #4
        bne @i
        ; ---- explosions (slots 11..14)
        ldx #$0000
@b:     stx loopi
        lda X_T,x
        beq @bn
        lda X_X,x
        sta tmp0
        lda X_Y,x
        sta tmp1
        lda X_T,x
        and #$04
        beq :+
        lda #10
        bra :++
:       lda #12
:       sta spr_tile
        A16
        txa
        lsr
        clc
        adc #11
        sta spr_slot
        A8
        jsr set_small_xy
        lda #$34
        sta spr_attr
        jsr put_sprite
@bn:    ldx loopi
        inx
        inx
        cpx #8
        bne @b
        rts
.endproc

; -----------------------------------------------------------------------------
;  Game states
; -----------------------------------------------------------------------------
.proc enter_title
        .a8
        .i16
        lda #$80
        sta INIDISP
        stz NMITIMEN
        lda #ST_TITLE
        sta state
        lda #0
        jsr load_picture
        jsr clear_bg3
        ; logo: 18x3 tiles at row 4, col 7
        ldx #$0000
        stx tmp0
        ldy #$0000
@lr:    A16
        lda tmp0
        asl
        asl
        asl
        asl
        asl
        asl
        clc
        adc #(4*64 + 7*2)
        tax
        A8
        lda #18
        sta tmp1
@lc:    lda title_map,y
        sta f:BG3MAP,x
        lda title_map+1,y
        sta f:BG3MAP+1,x
        inx
        inx
        iny
        iny
        dec tmp1
        bne @lc
        inc tmp0
        lda tmp0
        cmp #3
        bne @lr
        PRINT 9, 7, s_sub, ATTR_W
        PRINT 21, 5, s_help1, ATTR_W
        PRINT 23, 5, s_help2, ATTR_W
        PRINT 25, 9, s_hi, ATTR_Y
        ldx #(25*64 + 12*2)
        lda hiscore+2
        jsr put_bcd
        lda hiscore+1
        jsr put_bcd
        lda hiscore
        jsr put_bcd
        lda #0
        jsr put_digit
        jsr upload_bg3
        jsr build_oam
        jsr upload_oam
        lda #$16
        sta tm_val
        sta TM
        stz bg1_dirty
        stz bg3_dirty
        lda #$0F
        sta bright
        sta INIDISP
        lda RDNMI
        lda #$81
        sta NMITIMEN
        rts
.endproc

.proc st_title
        .a8
        .i16
        ; blink PRESS START
        lda nmi_count
        and #$1F
        bne @inp
        lda nmi_count
        and #$20
        beq @on
        lda #18
        jsr clear_row
        bra @inp
@on:    PRINT 18, 10, s_press, ATTR_Y
@inp:   A16
        lda joy_new
        and #BTN_START
        A8
        beq @done
        ; start a new game
        A16
        lda rng
        eor nmi_count
        ora #$0001
        sta rng
        stz score
        stz score+2
        A8
        lda #3
        sta lives
        lda #1
        sta stage
        jsr load_stage
        SFX 2, jingle_start
@done:  rts
.endproc

.proc load_stage
        .a8
        .i16
        lda #$80
        sta INIDISP
        stz NMITIMEN
        lda stage
        dec a
        jsr load_picture
        jsr init_field
        jsr redraw_all
        jsr upload_bg1
        ldx #$0000
        stx claimed
        stz pct
        stz paused
        jsr clear_bg3
        jsr draw_hud
        jsr init_entities
        PRINT 13, 12, s_stage, ATTR_Y
        ldx #(13*64 + 18*2)
        lda stage
        jsr put_dec2
        PRINT 15, 12, s_ready, ATTR_W
        jsr upload_bg3
        lda #ST_READY
        sta state
        ldx #120
        stx timer
        jsr calc_ppos
        jsr build_oam
        jsr upload_oam
        lda #$17
        sta tm_val
        sta TM
        stz bg1_dirty
        stz bg3_dirty
        lda #$0F
        sta bright
        sta INIDISP
        lda RDNMI
        lda #$81
        sta NMITIMEN
        rts
.endproc

.proc st_ready
        .a8
        .i16
        A16
        dec timer
        A8
        bne @r
        lda #13
        jsr clear_row
        lda #15
        jsr clear_row
        lda #ST_PLAY
        sta state
        jsr music_start
@r:     rts
.endproc

.proc st_play
        .a8
        .i16
        A16
        lda joy_new
        and #BTN_START
        A8
        beq @np
        lda paused
        eor #1
        sta paused
        beq @unp
        PRINT 14, 13, s_paused, ATTR_Y
        jsr music_stop
        bra @np
@unp:   lda #14
        jsr clear_row
        jsr music_start
@np:    lda paused
        beq :+
        rts
:       jsr player_update
        jsr calc_ppos
        lda state
        cmp #ST_PLAY
        bne @r
        jsr enemies_update
        jsr timers_update
@r:     jmp booms_update
.endproc

.proc st_dying
        .a8
        .i16
        jsr booms_update
        A16
        dec timer
        A8
        beq :+
        rts
:       ; remove the trail
        ldx #$0000
        stx loopi
@t:     A16
        lda loopi
        cmp trail_len
        bcs @td
        asl
        tax
        lda f:TRAIL,x
        tax
        A8
        stz GRID,x
        jsr update_cell
        A16
        inc loopi
        bra @t
@td:    A8
        ldx #$0000
        stx trail_len
        lda pmode
        beq :+
        ldx start_idx
        stx p_idx
:       stz pmode
        jsr calc_ppos
        dec lives
        jsr draw_hud
        lda lives
        bne :+
        jmp enter_gameover
:       ldx #120
        stx invuln
        lda #ST_PLAY
        sta state
        jmp music_start
.endproc

.proc enter_clear
        .a8
        .i16
        jsr music_stop
        lda #ST_CLEAR
        sta state
        ldx #240
        stx timer
        lda #$16
        sta tm_val
        ; bonus = (pct - 80) * 100 units + 500
        A16
        lda pct
        and #$00FF
        sec
        sbc #80
        sta tmp0
        asl
        asl
        asl
        asl
        asl
        sta tmp1                ; *32
        asl
        sta tmp2                ; *64
        lda tmp0
        asl
        asl                     ; *4
        clc
        adc tmp1
        adc tmp2                ; *100
        adc #50
        jsr bin2bcd
        sta bonus
        jsr add_score
        A8
        jsr draw_hud
        PRINT 12, 10, s_clear, ATTR_Y
        PRINT 15, 9, s_bonus, ATTR_W
        ldx #(15*64 + 16*2)
        lda #ATTR_Y
        sta text_attr
        lda bonus+1
        jsr put_bcd
        lda bonus
        jsr put_bcd
        lda #0
        jsr put_digit
        SFX 2, jingle_clear
        rts
.endproc

.proc st_clear
        .a8
        .i16
        A16
        dec timer
        A8
        bne @r
        lda stage
        cmp #99
        bcs :+
        inc stage
:       jsr load_stage
        SFX 2, jingle_start
@r:     rts
.endproc

.proc enter_gameover
        .a8
        .i16
        lda #ST_OVER
        sta state
        ldx #300
        stx timer
        PRINT 14, 11, s_over, ATTR_Y
        ; hiscore
        A16
        lda score+2
        cmp hiscore+2
        bcc @nohi
        bne @hi
        lda score
        cmp hiscore
        bcc @nohi
@hi:    lda score
        sta hiscore
        lda score+2
        sta hiscore+2
@nohi:  A8
        SFX 2, jingle_over
        rts
.endproc

.proc st_over
        .a8
        .i16
        A16
        dec timer
        beq @go
        lda timer
        cmp #200
        bcs @r
        lda joy_new
        and #BTN_START
        beq @r
@go:    A8
        jmp enter_title
@r:     A8
        rts
.endproc

; -----------------------------------------------------------------------------
;  Sound: tiny SPC700 driver that writes DSP registers on request
; -----------------------------------------------------------------------------
.proc spc_init
        .a8
        .i16
        A16
@w:     lda APUIO0
        cmp #$BBAA
        bne @w
        A8
        ldx #$0200
        stx APUIO2
        lda #$01
        sta APUIO1
        lda #$CC
        sta APUIO0
@w1:    cmp APUIO0
        bne @w1
        ldy #$0000
@l:     lda spc_blob,y
        sta APUIO1
        tya
        sta APUIO0
@w2:    cmp APUIO0
        bne @w2
        iny
        cpy #(spc_blob_end - spc_blob)
        bne @l
        ldx #$0200
        stx APUIO2
        stz APUIO1
        tya
        clc
        adc #1
        bne :+
        inc a
:       sta APUIO0
@w3:    cmp APUIO0
        bne @w3
        sta apu_cnt
        DSPW $6C, $20           ; FLG: echo writes off, unmute
        DSPW $0C, $60           ; main volume
        DSPW $1C, $60
        DSPW $2C, $00
        DSPW $3C, $00
        DSPW $4D, $00           ; EON
        DSPW $3D, $02           ; NON: voice 1 is noise
        DSPW $2D, $00           ; PMON
        DSPW $5D, $03           ; sample directory at $0300
        DSPW $6D, $70
        DSPW $7D, $00
        DSPW $5C, $00           ; KOF
        DSPW $04, $00           ; voice 0: square
        DSPW $05, $00
        DSPW $07, $7F
        DSPW $00, $00
        DSPW $01, $00
        DSPW $14, $00           ; voice 1: noise
        DSPW $15, $00
        DSPW $17, $7F
        DSPW $10, $00
        DSPW $11, $00
        DSPW $24, $01           ; voice 2: triangle
        DSPW $25, $00
        DSPW $27, $7F
        DSPW $20, $00
        DSPW $21, $00
        DSPW $34, $01           ; voice 3: triangle (music)
        DSPW $35, $00
        DSPW $37, $7F
        DSPW $30, $00
        DSPW $31, $00
        rts
.endproc

.proc music_start
        .a8
        .i16
        SFX 3, music
        rts
.endproc

.proc music_stop
        .a8
        .i16
        ldx #$0000
        stx ch_ptr+6
        DSPW $30, $00
        DSPW $31, $00
        rts
.endproc

.proc apu_write
        .a8
        .i16
        phx
        lda apu_reg
        sta APUIO1
        lda apu_val
        sta APUIO2
        inc apu_cnt
        lda apu_cnt
        sta APUIO0
        ldx #$0800
@w:     cmp APUIO0
        beq @ok
        dex
        bne @w
@ok:    plx
        rts
.endproc

; X = sfx data pointer, Y = channel*2
.proc sfx_start
        .a8
        .i16
        stx ch_ptr,y
        lda #1
        sta a:ch_timer,y
        sta a:ch_new,y
        rts
.endproc

kon_bits: .byte $01, 0, $02, 0, $04, 0, $08, 0

.proc ch_base                   ; X = channel*2 -> A = voice*16
        .a8
        .i16
        txa
        asl
        asl
        asl
        rts
.endproc

.proc sfx_update
        .a8
        .i16
        ldx #$0000
@ch:    stx sfx_ch
        A16
        lda ch_ptr,x
        A8
        bne :+
        jmp @next
:       A16
        sta sptr
        A8
        dec ch_timer,x
        beq :+
        jmp @next
:       ldy #$0000
        lda (sptr),y
        cmp #$FF
        bne :+
        ldy #.loword(music)     ; loop the music track
        sty ch_ptr,x
        lda #1
        sta ch_timer,x
        jmp @next
:       cmp #0
        bne @step
        stz ch_ptr,x
        stz ch_ptr+1,x
        jsr ch_base
        sta apu_reg
        stz apu_val
        jsr apu_write
        inc apu_reg
        jsr apu_write
        bra @next
@step:  sta ch_timer,x
        cpx #2
        beq @noise
        jsr ch_base
        ora #2
        sta apu_reg
        ldy #1
        lda (sptr),y
        sta apu_val
        jsr apu_write
        inc apu_reg
        iny
        lda (sptr),y
        sta apu_val
        jsr apu_write
        bra @vol
@noise: lda #$6C
        sta apu_reg
        ldy #1
        lda (sptr),y
        ora #$20
        sta apu_val
        jsr apu_write
@vol:   jsr ch_base
        sta apu_reg
        ldy #3
        lda (sptr),y
        sta apu_val
        jsr apu_write
        inc apu_reg
        jsr apu_write
        lda ch_new,x
        beq @adv
        stz ch_new,x
        lda #$4C
        sta apu_reg
        lda kon_bits,x
        sta apu_val
        jsr apu_write
@adv:   A16
        lda sptr
        clc
        adc #4
        sta ch_ptr,x
        A8
@next:  ldx sfx_ch
        inx
        inx
        cpx #8
        beq :+
        jmp @ch
:       rts
.endproc

; =============================================================================
.segment "RODATA"
zero_byte: .byte 0

.macro NOTE dur, pitch, vol
        .byte dur, <(pitch), >(pitch), vol
.endmacro

sfx_cut:
        NOTE 2, 1606, $30
        NOTE 3, 2144, $24
        .byte 0
sfx_claim:
        NOTE 3, 1072, $40
        NOTE 3, 1350, $40
        NOTE 3, 1606, $40
        NOTE 4, 2144, $40
        NOTE 4, 2144, $20
        NOTE 4, 2144, $10
        .byte 0
sfx_item:
        NOTE 3, 2701, $40
        NOTE 3, 3211, $40
        NOTE 3, 4287, $40
        NOTE 8, 4287, $20
        .byte 0
sfx_death:
        NOTE 4, 28, $70
        NOTE 6, 24, $60
        NOTE 8, 20, $48
        NOTE 10, 16, $30
        NOTE 12, 12, $18
        NOTE 12, 8, $0C
        .byte 0
sfx_kill:
        NOTE 3, 30, $60
        NOTE 4, 26, $40
        NOTE 6, 22, $20
        .byte 0
jingle_start:
        NOTE 8, 2142, $50
        NOTE 8, 2699, $50
        NOTE 8, 3211, $50
        NOTE 16, 4288, $50
        NOTE 12, 4288, $20
        .byte 0
jingle_clear:
        NOTE 6, 2142, $50
        NOTE 6, 2699, $50
        NOTE 6, 3211, $50
        NOTE 6, 4288, $50
        NOTE 6, 5402, $50
        NOTE 6, 6423, $50
        NOTE 24, 8573, $50
        NOTE 16, 8573, $20
        .byte 0
jingle_over:
        NOTE 14, 1606, $50
        NOTE 14, 1351, $50
        NOTE 14, 1072, $50
        NOTE 30, 803, $50
        NOTE 20, 803, $20
        .byte 0

music:
        NOTE 6, 451, $28
        NOTE 2, 451, $0C
        NOTE 6, 675, $28
        NOTE 2, 675, $0C
        NOTE 6, 901, $28
        NOTE 2, 901, $0C
        NOTE 6, 675, $28
        NOTE 2, 675, $0C
        NOTE 6, 1072, $28
        NOTE 2, 1072, $0C
        NOTE 6, 675, $28
        NOTE 2, 675, $0C
        NOTE 6, 901, $28
        NOTE 2, 901, $0C
        NOTE 6, 675, $28
        NOTE 2, 675, $0C
        NOTE 6, 358, $28
        NOTE 2, 358, $0C
        NOTE 6, 536, $28
        NOTE 2, 536, $0C
        NOTE 6, 715, $28
        NOTE 2, 715, $0C
        NOTE 6, 536, $28
        NOTE 2, 536, $0C
        NOTE 6, 901, $28
        NOTE 2, 901, $0C
        NOTE 6, 536, $28
        NOTE 2, 536, $0C
        NOTE 6, 715, $28
        NOTE 2, 715, $0C
        NOTE 6, 536, $28
        NOTE 2, 536, $0C
        NOTE 6, 401, $28
        NOTE 2, 401, $0C
        NOTE 6, 601, $28
        NOTE 2, 601, $0C
        NOTE 6, 803, $28
        NOTE 2, 803, $0C
        NOTE 6, 601, $28
        NOTE 2, 601, $0C
        NOTE 6, 1011, $28
        NOTE 2, 1011, $0C
        NOTE 6, 601, $28
        NOTE 2, 601, $0C
        NOTE 6, 803, $28
        NOTE 2, 803, $0C
        NOTE 6, 601, $28
        NOTE 2, 601, $0C
        NOTE 6, 337, $28
        NOTE 2, 337, $0C
        NOTE 6, 506, $28
        NOTE 2, 506, $0C
        NOTE 6, 675, $28
        NOTE 2, 675, $0C
        NOTE 6, 506, $28
        NOTE 2, 506, $0C
        NOTE 6, 851, $28
        NOTE 2, 851, $0C
        NOTE 6, 506, $28
        NOTE 2, 506, $0C
        NOTE 6, 675, $28
        NOTE 2, 675, $0C
        NOTE 6, 506, $28
        NOTE 2, 506, $0C
        .byte $FF

spc_blob:
        ; $0200: driver
        .byte $20                       ; clrp
        .byte $CD, $EF                  ; mov x,#$ef
        .byte $BD                       ; mov sp,x
        .byte $E4, $F4                  ; mov a,$f4
        .byte $C4, $00                  ; mov $00,a
        .byte $E4, $F4                  ; loop: mov a,$f4
        .byte $64, $00                  ; cmp a,$00
        .byte $F0, $FA                  ; beq loop
        .byte $C4, $00                  ; mov $00,a
        .byte $E4, $F5                  ; mov a,$f5
        .byte $C4, $F2                  ; mov $f2,a
        .byte $E4, $F6                  ; mov a,$f6
        .byte $C4, $F3                  ; mov $f3,a
        .byte $E4, $00                  ; mov a,$00
        .byte $C4, $F4                  ; mov $f4,a
        .byte $2F, $EA                  ; bra loop
        .res $0300 - $0200 - 30, 0
        ; $0300: sample directory
        .word $0400, $0400, $0410, $0410
        .res $0400 - $0308, 0
        ; $0400: square wave (16 samples)
        .byte $B3, $77, $77, $77, $77, $99, $99, $99, $99
        .res 7, 0
        ; $0410: triangle wave (32 samples)
        .byte $B0, $01, $23, $45, $67, $76, $54, $32, $10
        .byte $B3, $FE, $DC, $BA, $98, $89, $AB, $CD, $EF
spc_blob_end:

trail_cols:
        .word RGB(255,220,40), RGB(255,250,140), RGB(255,255,255), RGB(255,250,140)
        .word RGB(255,220,40), RGB(255,150,20), RGB(255,90,0), RGB(255,150,20)

bg3_pal:
        .word RGB(0,0,0), RGB(255,255,255), RGB(16,16,40), RGB(160,200,255)
        .word RGB(0,0,0), RGB(255,230,80), RGB(40,16,0), RGB(255,140,40)
        .word RGB(0,0,0), RGB(40,170,255), RGB(8,8,40), RGB(230,250,255)
bg1_pal:
        .word RGB(0,0,0), RGB(14,18,52), RGB(52,64,130), RGB(210,240,255)
        .word RGB(255,220,40), RGB(90,130,200), 0, 0
        .word 0, 0, 0, 0, 0, 0, 0, 0

title_map: .incbin "title.map"

s_score:  .asciiz "SCORE"
s_stage:  .asciiz "STAGE"
s_area:   .asciiz "AREA   %/80%"
s_lives:  .asciiz "LIVES"
s_ready:  .asciiz "READY!"
s_paused: .asciiz "PAUSED"
s_clear:  .asciiz "STAGE CLEAR!"
s_bonus:  .asciiz "BONUS"
s_over:   .asciiz "GAME OVER"
s_press:  .asciiz "PRESS START"
s_sub:    .asciiz "RECLAIM THE NEBULA"
s_help1:  .asciiz "HOLD B AND MOVE TO CUT"
s_help2:  .asciiz "CLAIM 80% OF THE FIELD"
s_hi:     .asciiz "HI"
s_speed:  .asciiz "SPEED UP!"
s_shield: .asciiz "SHIELD ON!"
s_freeze: .asciiz "ENEMIES FROZEN!"
s_1up:    .asciiz "EXTRA LIFE!"

pic_chr_lo:  .word .loword(pic0_chr), .loword(pic1_chr), .loword(pic2_chr), .loword(pic3_chr)
pic_bank:    .word ^pic0_chr, ^pic1_chr, ^pic2_chr, ^pic3_chr
pic_chr_len: .word pic0_chr_end-pic0_chr, pic1_chr_end-pic1_chr, pic2_chr_end-pic2_chr, pic3_chr_end-pic3_chr
pic_map_lo:  .word .loword(pic0_map), .loword(pic1_map), .loword(pic2_map), .loword(pic3_map)
pic_pal_lo:  .word .loword(pic0_pal), .loword(pic1_pal), .loword(pic2_pal), .loword(pic3_pal)

; =============================================================================
.segment "BANK1"
pic0_chr: .incbin "pic0.chr"
pic0_chr_end:
pic0_map: .incbin "pic0.map"
pic0_pal: .incbin "pic0.pal"

.segment "BANK2"
pic1_chr: .incbin "pic1.chr"
pic1_chr_end:
pic1_map: .incbin "pic1.map"
pic1_pal: .incbin "pic1.pal"

.segment "BANK3"
pic2_chr: .incbin "pic2.chr"
pic2_chr_end:
pic2_map: .incbin "pic2.map"
pic2_pal: .incbin "pic2.pal"

.segment "BANK4"
pic3_chr: .incbin "pic3.chr"
pic3_chr_end:
pic3_map: .incbin "pic3.map"
pic3_pal: .incbin "pic3.pal"

.segment "BANK5"
bg_tiles:   .incbin "bgtiles.bin"
font_tiles: .incbin "font.bin"
font_end:
obj_tiles:  .incbin "sprites.bin"
obj_pal:    .incbin "objpal.bin"

; =============================================================================
.segment "HEADER"
        .res 16, 0                      ; $FFB0
        .byte "NOLFIED              "   ; $FFC0 title (21 bytes)
        .byte $20                       ; LoROM, SlowROM
        .byte $00                       ; ROM only
        .byte $08                       ; 256KB
        .byte $00                       ; no SRAM
        .byte $01                       ; North America
        .byte $00                       ; developer
        .byte $00                       ; version
        .word $FFFF, $0000              ; checksum complement / checksum
        ; native vectors $FFE0
        .word 0, 0
        .word irq_stub                  ; COP
        .word irq_stub                  ; BRK
        .word irq_stub                  ; ABORT
        .word nmi                       ; NMI
        .word 0
        .word irq_stub                  ; IRQ
        ; emulation vectors $FFF0
        .word 0, 0
        .word irq_stub                  ; COP
        .word 0
        .word irq_stub                  ; ABORT
        .word irq_stub                  ; NMI
        .word reset                     ; RESET
        .word irq_stub                  ; IRQ/BRK
