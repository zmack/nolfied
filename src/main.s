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
I_X      = $05A0            ; items: 4 slots
I_Y      = $05A8
I_ON     = $05B0
; roguelite / juice state (absolute RAM, survives init_entities)
PERKS    = $0600            ; 16 perk stack counts
OFFERS   = $0610            ; 3 perks on offer
P_TOTAL  = $0614
CHAIN    = $0615
KILLS    = $0616
AEGIS_C  = $0617
GOAL     = $0618            ; word
SHAKE_T  = $061A
SH_X     = $061B
SH_Y     = $061C
FL_R     = $061D
FL_G     = $061E
FL_B     = $061F
JACKMULT = $0620            ; word
PLUSM    = $0622            ; word
XM       = $0624            ; word
MULT     = $0626            ; word
CHIPS_B  = $0628            ; word, BCD
PROD     = $062A            ; 4 bytes BCD
PRN      = $062E            ; 4 bytes BCD print buffer
SCR_H    = $0632            ; word
SCR_V    = $0634            ; word
N_ITEMS  = $0636            ; word (count*2)
M_A      = $0638
M_B      = $0639
M_RES    = $063A            ; word
GW       = $063C
GR       = $063D
GK       = $063E            ; word
CURSOR   = $0640            ; word
NZ_ON    = $0642
CS_V     = $0644            ; word
CS_T     = $0646            ; word
CT_COL   = $0648            ; word
CT_P     = $064A            ; word
CT_L     = $064C            ; word
DC_C0    = $064E            ; word
DC_R     = $0650            ; word
DC_C     = $0652            ; word
DC_FR    = $0654
DC_IN    = $0655
CHAIN_T  = $0656            ; word: frames until the chain breaks
CHAIN_BAR = $0658
REROLLS  = $0659
RUN_END  = $0660
; state-machine bookkeeping (outside the per-run area)
FSM_ERRS = $0670            ; number of illegal transitions / invariant faults
FSM_KIND = $0671            ; 1 game state, 2 player mode, 3 trail invariant
FSM_FROM = $0672
FSM_TO   = $0673
FSM_NEW  = $0674            ; word
FSM_TMP  = $0676            ; word
APU_DEAD = $0678            ; sound CPU stopped answering: never touch it again
LOOPS    = $067A            ; word: main-loop iterations (frame pacing tests)

P_GREED   = 0
P_CHAIN   = 1
P_TITAN   = 2
P_SNIPER  = 3
P_HUNTER  = 4
P_SWIFT   = 5
P_AEGIS   = 6
P_STASIS  = 7
P_CHRONO  = 8
P_PHOENIX = 9
P_LUCKY   = 10
P_PRISM   = 11
P_GLASS   = 12
P_QUOTA   = 13
P_JACKPOT = 14
P_MIDAS   = 15

CGWSEL   = $2130
CGADSUB  = $2131
COLDATA  = $2132
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
ST_DRAFT = 6
ST_PAUSE = 7
ST_BOOT  = 8                ; only ever the initial value

PM_EDGE    = 0
PM_DRAW    = 1
PM_RETRACT = 2

BTN_START = $1000
BTN_CUT   = $C0C0           ; B, Y, A or X

ATTR_W = $20                ; BG3 text: priority, palette 0 (white)
ATTR_Y = $24                ; palette 1 (yellow)
ATTR_G = $2C                ; palette 3 (green)
ATTR_P = $30                ; palette 4 (pink)
ATTR_O = $34                ; palette 5 (orange)

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

.ifdef BENCH
BENCH_OUT = $7E8000
BENCH_N   = 40
B_I       = $06F0               ; word: vector offset (i * 24)
B_O       = $06F2               ; word: output offset (i * 16)

.macro STAMP off
        lda $2137               ; latch H/V
        lda $213F               ; reset the lo/hi toggle
        lda $213C
        sta f:BENCH_OUT+off,x
        lda $213C
        and #$01
        sta f:BENCH_OUT+off+1,x
        lda $213D
        sta f:BENCH_OUT+off+2,x
        lda $213D
        and #$01
        sta f:BENCH_OUT+off+3,x
        lda nmi_count
        sta f:BENCH_OUT+off+4,x
.endmacro
.endif

; =============================================================================
.segment "ZEROPAGE"
nmi_count:   .res 1
frame_ready: .res 1
bg1_dirty:   .res 1
bg3_dirty:   .res 1
tm_val:      .res 1
bright:      .res 1
state:       .res 1
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
view_state:  .res 1
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
.ifdef BENCH
        jmp run_bench           ; benchmark build: score test vectors and stop
.endif
        A16
        lda #$ACE1
        sta rng
        A8
        lda #ST_BOOT
        sta state
        lda #ST_TITLE
        jsr goto_state

main_loop:
        A16
        inc LOOPS
        A8
        jsr read_joy
        jsr juice_update
        jsr sfx_update
        A16
        lda state
        and #$00FF
        asl
        tax
        A8
        jsr (state_tab,x)
        jsr fsm_check
        lda state
        jsr build_oam
        ; publish the frame, then sleep until the NMI has uploaded it. Waiting
        ; on frame_ready (not nmi_count) cannot miss an NMI that lands right
        ; after the publish - see spec/FrameSync.tla.
        lda #$01
        sta frame_ready
@wait:  lda frame_ready
        bne @wait
        jmp main_loop
.endproc

state_tab:
        .word st_title, st_ready, st_play, st_dying, st_clear, st_over, st_draft, st_pause

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
        ldx #($5000 + 3*32)
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
        ldx #$5800
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
        lda SCR_H
        sta BG1HOFS
        lda SCR_H+1
        sta BG1HOFS
        lda SCR_H
        sta BG2HOFS
        lda SCR_H+1
        sta BG2HOFS
        lda SCR_V
        sta BG1VOFS
        lda SCR_V+1
        sta BG1VOFS
        lda SCR_V
        sta BG2VOFS
        lda SCR_V+1
        sta BG2VOFS
        lda FL_R
        ora #$20
        sta COLDATA
        lda FL_G
        ora #$40
        sta COLDATA
        lda FL_B
        ora #$80
        sta COLDATA
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
        VRAM_LOAD icon_tiles, $7000, 8192
        VRAM_LOAD mini_tiles, $43C0, 256
        CGRAM_LOAD bg3_pal, 0, 48
        CGRAM_LOAD bg1_pal, 32, 32
        CGRAM_LOAD card_pals, 64, 96
        CGRAM_LOAD obj_pal, 128, 128
        CGRAM_LOAD icon_pal, 192, 32
        stz CGWSEL              ; colour math: add fixed colour (screen flashes)
        lda #$3F
        sta CGADSUB
        lda #$E0
        sta COLDATA
        ldx #$03FF
        stx SCR_V
        lda #$09                ; mode 1, BG3 high priority
        sta BGMODE
        lda #$50
        sta BG1SC
        lda #$54
        sta BG2SC
        lda #$58
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
        ldx #$5000
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
        ldx #$5800
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
        ldx #$5400
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
        PRINT 2, 19, s_chain, ATTR_W
        lda #ATTR_Y
        sta text_attr
        ldx #(1*64 + 7*2)
        lda score+3
        jsr put_digit
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
        ldx #(2*64 + 10*2)
        lda GOAL
        jsr put_dec2
        ldx #(2*64 + 14*2)
        lda #$0A                ; '*' heart is ASCII 42 -> tile 10
        sta f:BG3MAP,x
        lda #ATTR_P
        sta f:BG3MAP+1,x
        inx
        inx
        lda lives
        jsr put_digit
        lda #ATTR_O
        sta text_attr
        ldx #(2*64 + 25*2)
        lda CHAIN
        jsr put_dec2
        ldx #$0000
        jsr draw_owned
        lda #$FF
        sta CHAIN_BAR
        jsr draw_chain_bar
        lda #$01
        sta bg3_dirty
        rts
.endproc

; 4-cell bar at row 2, col 28: time left before the chain breaks
.proc draw_chain_bar
        .a8
        .i16
        lda CHAIN
        bne :+
        lda #0
        bra @have
:       A16
        lda CHAIN_T
        clc
        adc #149
        sta WRDIVL
        A8
        lda #150
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
@have:  cmp CHAIN_BAR
        bne :+
        rts
:       sta CHAIN_BAR
        sta tmp3
        ldx #(2*64 + 28*2)
        ldy #4
@l:     lda tmp3
        beq @blank
        dec tmp3
        lda #('=' - 32)
        sta f:BG3MAP,x
        lda CHAIN_BAR
        cmp #2
        lda #ATTR_O
        bcs :+
        lda #ATTR_P
:       sta f:BG3MAP+1,x
        bra @n
@blank: lda #0
        sta f:BG3MAP,x
        sta f:BG3MAP+1,x
@n:     inx
        inx
        dey
        bne @l
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
        jsr redraw_all
        jsr check_enclosed
        jsr score_claim
        jsr snap_player
        jsr draw_hud
        lda pct
        cmp GOAL
        bcc @nc
        lda #ST_CLEAR
        jmp goto_state
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
        inc KILLS
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
        cpx #8
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
        lda PERKS+P_JACKPOT     ; JACKPOT: +4 mult per stack for this stage
        asl
        asl
        A16
        and #$00FF
        clc
        adc JACKMULT
        sta JACKMULT
        A8
        lda #6
        sta FL_R
        sta FL_G
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
        jsr set_pmode
        bra @move
@doret: jsr retract_step        ; retract at 2 cells per frame
        lda pmode
        cmp #PM_RETRACT
        bne :+
        jsr retract_step
:       rts
@notret:
        cmp #PM_DRAW
        bne @move
        lda tmp0
        ora tmp0+1
        bne @move
        lda #PM_RETRACT
        jmp set_pmode
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
        jsr set_pmode
        SFX 0, sfx_cut
        bra @add
@drawing:
        lda tmp3
        beq @add
        cmp #C_EDGE
        bne @fail
        ldx tmp2
        stx p_idx
        jsr calc_ppos
        jsr do_fill             ; may enter ST_CLEAR
        ldx #$0000              ; the trail is now claimed area:
        stx trail_len           ; mode and trail change together
        lda #PM_EDGE
        jsr set_pmode
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
        jmp set_pmode
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
        jsr update_cell
        A16
        lda trail_len
        A8
        bne :+
        lda #PM_EDGE            ; trail empty: back on the edge this same step
        jmp set_pmode
:       rts
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
        lda AEGIS_C
        beq @die
        dec AEGIS_C             ; AEGIS soaks the hit
        jsr wipe_trail
        ldx #90
        stx invuln
        lda #10
        sta FL_G
        lda #16
        sta FL_B
        lda #12
        sta SHAKE_T
        ldx #.loword(s_aegis)
        jsr show_msg
        SFX 1, sfx_kill
        rts
@die:   lda #ST_DYING
        jmp goto_state
@no:    rts
.endproc

.proc enter_dying
        .a8
        .i16
        stz CHAIN
        jsr draw_chain_bar
        lda #18
        sta FL_R
        lda #3
        sta FL_G
        sta FL_B
        lda #24
        sta SHAKE_T
        ldx #90
        stx timer
        lda ppx
        sta boom_x
        lda ppy
        sta boom_y
        jsr spawn_boom
        jsr music_stop
        SFX 1, sfx_death
        rts
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
        stz pmode               ; FSM reset: every stage starts on the edge
        ldx #$0000
        stx trail_len
        lda #2
        sta pspeed
        lda PERKS+P_SWIFT
        beq :+
        dec pspeed
:       lda #1
        sta pmove_timer
        stz KILLS
        ldx #600
        stx CHAIN_T
        stz SHAKE_T
        stz FL_R
        stz FL_G
        stz FL_B
        lda PERKS+P_AEGIS
        sta AEGIS_C
        A16
        stz JACKMULT
        lda PERKS+P_QUOTA
        and #$00FF
        sta GOAL
        asl
        asl
        clc
        adc GOAL                ; quota * 5
        eor #$FFFF
        sec
        adc #80
        sta GOAL
        A8
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
:       jsr chrono_scale
        sta E_SPD
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
:       jsr chrono_scale
        sta E_SPD,x
        A8
        jsr randomize_vel
        inx
        inx
        dec tmp3
        bne @m
        ; items: 2 + LUCKY
        A16
        lda PERKS+P_LUCKY
        and #$00FF
        clc
        adc #2
        asl
        sta N_ITEMS
        A8
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
        cpx N_ITEMS
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
        beq @chain
        dec msg_timer
        bne @chain
        A8
        lda #27
        jsr clear_row
@chain: A8
        lda CHAIN
        beq @done
        A16
        lda CHAIN_T
        beq @brk
        dec CHAIN_T
        A8
        jmp draw_chain_bar
@brk:   A8
        stz CHAIN
        jsr draw_hud
        ldx #.loword(s_broken)
        jsr show_msg
        SFX 0, sfx_tick
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
        jsr add_shake_x
        A8
        lda tmp1
        clc
        adc #15
        clc
        adc SH_Y
        sta spr_y
        stz spr_big
        rts
.endproc

.proc build_oam                 ; A = the game state to draw sprites for
        .a8
        .i16
        sta view_state
        ldx #$0000
@h:     stz OAM_BUF,x
        lda #224
        sta OAM_BUF+1,x
        inx
        inx
        inx
        inx
        cpx #80
        bne @h
        stz OAM_HI
        stz OAM_HI+1
        stz OAM_HI+2
        stz OAM_HI+3
        stz OAM_HI+4
        lda view_state
        cmp #ST_DRAFT
        bne :+
        jmp draft_oam
:       lda state
        cmp #ST_READY
        beq @show
        cmp #ST_PLAY
        beq @show
        cmp #ST_PAUSE
        beq @show
        cmp #ST_DYING
        beq @show
        rts
@show:
        ; ---- player (slot 0)
        lda view_state
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
        jsr add_shake_x
        A8
        lda E_Y+1
        clc
        adc #7
        clc
        adc SH_Y
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
        cpx #8
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
        adc #13
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
        lda hiscore+3
        jsr put_digit
        lda hiscore+2
        jsr put_bcd
        lda hiscore+1
        jsr put_bcd
        lda hiscore
        jsr put_bcd
        lda #0
        jsr put_digit
        jsr upload_bg3
        lda #ST_TITLE
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
        jsr new_run
        lda #ST_DRAFT
        jmp goto_state
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
        jsr init_entities
        jsr clear_bg3
        jsr draw_hud
        PRINT 13, 12, s_stage, ATTR_Y
        ldx #(13*64 + 18*2)
        lda stage
        jsr put_dec2
        PRINT 15, 12, s_ready, ATTR_W
        jsr upload_bg3
        ldx #120
        stx timer
        jsr calc_ppos
        lda #ST_READY
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
        lda #ST_PLAY
        jmp goto_state
@r:     rts
.endproc

.proc st_play
        .a8
        .i16
        A16
        lda joy_new
        and #BTN_START
        A8
        beq :+
        lda #ST_PAUSE
        jmp goto_state
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
:       jsr wipe_trail
        dec lives
        jsr draw_hud
        lda lives
        bne :+
        lda #ST_OVER
        jmp goto_state
:       ldx #120
        stx invuln
        lda #ST_PLAY
        jmp goto_state
.endproc

.proc enter_clear
        .a8
        .i16
        jsr music_stop
        ldx #240
        stx timer
        lda #$16
        sta tm_val
        ; bonus = (pct - 80) * 100 units + 500
        A16
        lda pct
        and #$00FF
        sec
        sbc GOAL
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
        stz PROD
        stz PROD+2
        A8
        lda PERKS+P_MIDAS       ; MIDAS multiplies the clear bonus
        inc a
        sta M_A
@mid:   A16
        sed
        clc
        lda PROD
        adc bonus
        sta PROD
        lda PROD+2
        adc #$0000
        sta PROD+2
        cld
        A8
        dec M_A
        bne @mid
        jsr add_prod
        stz SHAKE_T
        lda #20
        sta FL_R
        sta FL_G
        sta FL_B
        jsr draw_hud
        PRINT 12, 10, s_clear, ATTR_Y
        PRINT 15, 9, s_bonus, ATTR_W
        ldx #(15*64 + 16*2)
        lda #ATTR_Y
        sta text_attr
        jsr put_prod
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
:       lda #ST_DRAFT
        jmp goto_state
@r:     rts
.endproc

.proc enter_gameover
        .a8
        .i16
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
        lda #ST_TITLE
        jmp goto_state
@r:     A8
        rts
.endproc

; -----------------------------------------------------------------------------
;  Sound: tiny SPC700 driver that writes DSP registers on request
; -----------------------------------------------------------------------------
.proc spc_init
        .a8
        .i16
        ldx #$0000
        A16
@w:     lda APUIO0
        cmp #$BBAA
        beq :+
        dex
        bne @w
        A8
        bra @dead
:       A8
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
        ; wait for the driver to latch port0 and raise READY before the first
        ; request, otherwise it can mistake that request for an old one
        ldx #$0000
@w4:    lda APUIO1
        cmp #$A5
        beq @up
        dex
        bne @w4
@dead:  lda #1
        sta APU_DEAD
        rts
@up:
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
        lda APU_DEAD
        beq :+
        rts
:       phx
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
        lda #1                  ; no echo: the driver may still be reading the
        sta APU_DEAD            ; ports, so never write them again
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
;  Roguelite layer: perks, chips x mult scoring, juice, draft screen
; =============================================================================
.proc mul8                      ; M_RES = M_A * M_B
        .a8
        .i16
        lda M_A
        sta $4202
        lda M_B
        sta $4203
        nop
        nop
        nop
        nop
        A16
        lda $4216
        sta M_RES
        A8
        rts
.endproc

.proc add_plus                  ; PLUSM += M_RES
        .a8
        .i16
        A16
        lda PLUSM
        clc
        adc M_RES
        sta PLUSM
        A8
        rts
.endproc

.proc add_prod                  ; score += PROD (BCD)
        .a8
        .i16
        A16
        sed
        clc
        lda score
        adc PROD
        sta score
        lda score+2
        adc PROD+2
        sta score+2
        cld
        A8
        rts
.endproc

.proc put_prod                  ; print PROD without leading zeros at X
        .a8
        .i16
        A16
        lda PROD
        sta PRN
        lda PROD+2
        sta PRN+2
        A8
        jmp put_bcd32_nz
.endproc

.proc put_bcd32_nz              ; PRN = 4 BCD bytes (LE), X = map offset
        .a8
        .i16
        stz NZ_ON
        ldy #$0003
@b:     lda PRN,y
        pha
        lsr
        lsr
        lsr
        lsr
        jsr nz_digit
        pla
        and #$0F
        cpy #$0000
        bne :+
        inc NZ_ON               ; always print the last digit
:       jsr nz_digit
        dey
        bpl @b
        rts
.endproc

.proc nz_digit
        .a8
        .i16
        cmp #0
        bne @p
        pha
        lda NZ_ON
        bne @z
        pla
        rts
@z:     pla
@p:     pha
        lda #1
        sta NZ_ON
        pla
        jmp put_digit
.endproc

; Score a claim: CHIPS (cells) x MULT, Balatro style.
.proc score_claim
        .a8
        .i16
        A16
        lda #1
        sta PLUSM
        A8
        ; chain: each link is worth (1 + CHAIN perks)
        lda PERKS+P_CHAIN
        inc a
        sta M_A
        lda CHAIN
        sta M_B
        jsr mul8
        jsr add_plus
        ; greed: +2 per stack
        lda PERKS+P_GREED
        sta M_A
        lda #2
        sta M_B
        jsr mul8
        jsr add_plus
        ; sniper: +6 per stack on tiny claims
        A16
        lda newly
        cmp #40
        A8
        bcs :+
        lda PERKS+P_SNIPER
        sta M_A
        lda #6
        sta M_B
        jsr mul8
        jsr add_plus
:       ; hunter: +3 per stack per shard killed this stage
        lda PERKS+P_HUNTER
        sta M_A
        lda KILLS
        sta M_B
        jsr mul8
        lda M_RES
        sta M_A
        lda #3
        sta M_B
        jsr mul8
        jsr add_plus
        ; prism: +1 per stack per perk owned
        lda PERKS+P_PRISM
        sta M_A
        lda P_TOTAL
        sta M_B
        jsr mul8
        jsr add_plus
        ; jackpot capsules this stage
        A16
        lda JACKMULT
        sta M_RES
        A8
        jsr add_plus
        ; xmult: titan on big claims, glass always
        A16
        lda #1
        sta XM
        lda newly
        cmp #150
        A8
        bcc :+
        lda PERKS+P_TITAN
        inc a
        sta XM
:       lda PERKS+P_GLASS
        beq :+
        lda XM
        sta M_A
        lda #3
        sta M_B
        jsr mul8
        lda M_RES
        sta XM
:       A16
        stz MULT
        lda XM
        and #$00FF
        tax
@mx:    lda MULT
        clc
        adc PLUSM
        sta MULT
        dex
        bne @mx
        lda MULT
        cmp #1000
        bcc :+
        lda #999
        sta MULT
:       lda newly
        jsr bin2bcd
        sta CHIPS_B
        stz PROD
        stz PROD+2
        ldx MULT
@pl:    sed
        clc
        lda PROD
        adc CHIPS_B
        sta PROD
        lda PROD+2
        adc #$0000
        sta PROD+2
        cld
        dex
        bne @pl
        A8
        jsr add_prod
.ifdef BENCH
        ldx B_O                 ; benchmark: the arithmetic ends here
        STAMP 16
.endif
        ; ---- popup: "CHIPS X MULT = +POINTS"
        lda #27
        jsr clear_row
        lda #ATTR_Y
        sta text_attr
        A16
        lda MULT
        cmp #10
        A8
        bcc :+
        lda #ATTR_O
        sta text_attr
        A16
        lda MULT
        cmp #50
        A8
        bcc :+
        lda #ATTR_P
        sta text_attr
:       A16
        lda CHIPS_B
        sta PRN
        stz PRN+2
        A8
        ldx #(27*64 + 1*2)
        jsr put_bcd32_nz
        ldy #.loword(s_x)
        sty str_ptr
        jsr print
        A16
        lda MULT
        jsr bin2bcd
        sta PRN
        stz PRN+2
        A8
        jsr put_bcd32_nz
        ldy #.loword(s_eq)
        sty str_ptr
        jsr print
        jsr put_prod
        lda #0
        jsr put_digit
        ldx #180
        stx msg_timer
        ; ---- chain grows
        lda CHAIN
        cmp #99
        bcs :+
        inc CHAIN
:       ldx #600
        stx CHAIN_T
        jsr draw_chain_bar
        ; ---- juice: shake by size, flash by mult
        A16
        lda newly
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        cmp #14
        bcc :+
        lda #14
:       clc
        adc #6
        A8
        sta SHAKE_T
        A16
        lda MULT
        lsr
        lsr
        cmp #14
        bcc :+
        lda #14
:       clc
        adc #4
        A8
        sta FL_R
        sta FL_G
        sta FL_B
        ; ---- stasis: freeze foes 1.5s per stack
        lda PERKS+P_STASIS
        beq @done
        sta M_A
        lda #90
        sta M_B
        jsr mul8
        A16
        lda M_RES
        cmp freeze
        bcc :+
        sta freeze
:       A8
@done:  rts
.endproc

; clear the current trail and put the player back where the cut started
.proc wipe_trail
        .a8
        .i16
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
:       lda #PM_EDGE
        jsr set_pmode
        jmp calc_ppos
.endproc

; A16 speed -> A16 speed * (1 - 0.2 * CHRONO)
.proc chrono_scale
        .a16
        .i16
        phx
        sta CS_V
        sta WRDIVL
        A8
        lda #5
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
        lda RDDIVL
        sta CS_T
        lda PERKS+P_CHRONO
        and #$00FF
        tax
        lda CS_V
        cpx #0
        beq @d
@l:     sec
        sbc CS_T
        dex
        bne @l
@d:     plx
        rts
.endproc

.proc add_shake_x               ; spr_x += sign-extended SH_X
        .a16
        .i16
        lda SH_X
        and #$00FF
        cmp #$0080
        bcc :+
        ora #$FF00
:       clc
        adc spr_x
        sta spr_x
        rts
.endproc

shake_big:   .byte $FE, $FF, $01, $02
shake_small: .byte $FF, $00, $00, $01

.proc juice_update
        .a8
        .i16
        lda SHAKE_T
        beq @still
        dec SHAKE_T
        jsr rand8
        and #$03
        tax
        lda SHAKE_T
        cmp #10
        bcc @sm
        lda shake_big,x
        sta SH_X
        jsr rand8
        and #$03
        tax
        lda shake_big,x
        sta SH_Y
        bra @set
@sm:    lda shake_small,x
        sta SH_X
        jsr rand8
        and #$03
        tax
        lda shake_small,x
        sta SH_Y
        bra @set
@still: stz SH_X
        stz SH_Y
@set:   A16
        lda SH_X
        and #$00FF
        cmp #$0080
        bcc :+
        ora #$FF00
:       and #$03FF
        sta SCR_H
        lda SH_Y
        and #$00FF
        cmp #$0080
        bcc :+
        ora #$FF00
:       clc
        adc #$03FF
        and #$03FF
        sta SCR_V
        A8
        lda FL_R
        beq :+
        dec FL_R
:       lda FL_G
        beq :+
        dec FL_G
:       lda FL_B
        beq :+
        dec FL_B
:       rts
.endproc

.proc new_run
        .a8
        .i16
        ldx #$0000
@c:     stz PERKS,x
        inx
        cpx #(RUN_END - PERKS)
        bne @c
        ldx #80
        stx GOAL
        rts
.endproc

; X = BG3 map offset of a row: owned perk minis (+ stack count)
.proc draw_owned
        .a8
        .i16
        phx
        A16
        ldy #32
        lda #$0000
@c:     sta f:BG3MAP,x
        inx
        inx
        dey
        bne @c
        A8
        plx
        ldy #$0000
@p:     lda PERKS,y
        beq @n
        tya
        clc
        adc #120
        sta f:BG3MAP,x
        lda #ATTR_W
        sta f:BG3MAP+1,x
        inx
        inx
        lda PERKS,y
        cmp #2
        bcc @one
        lda #ATTR_Y
        sta text_attr
        lda PERKS,y
        jsr put_digit
        bra @n
@one:   inx
        inx
@n:     iny
        cpy #16
        bne @p
        lda #$01
        sta bg3_dirty
        rts
.endproc

; carry set if perk Y can be offered
.proc eligible
        .a8
        .i16
        lda PERKS,y
        cmp perk_max,y
        bcs @no
        tya
        cmp OFFERS
        beq @no
        cmp OFFERS+1
        beq @no
        cmp OFFERS+2
        beq @no
        sec
        rts
@no:    clc
        rts
.endproc

; pick 3 distinct perks, weighted by rarity
.proc gen_offers
        .a8
        .i16
        lda #$FF
        sta OFFERS
        sta OFFERS+1
        sta OFFERS+2
        ldx #$0000
        stx GK
@k:     stz GW
        ldy #$0000
@w:     jsr eligible
        bcc @wn
        lda perk_weight,y
        clc
        adc GW
        sta GW
@wn:    iny
        cpy #16
        bne @w
        lda GW
        bne :+
        lda #P_PHOENIX
        bra @store
:       jsr rand8
@mod:   cmp GW
        bcc @got
        sec
        sbc GW
        bra @mod
@got:   sta GR
        ldy #$0000
@f:     jsr eligible
        bcc @fn
        lda GR
        cmp perk_weight,y
        bcc @pick
        sec
        sbc perk_weight,y
        sta GR
@fn:    iny
        cpy #16
        bne @f
        lda #P_PHOENIX
        bra @store
@pick:  tya
@store: ldx GK
        sta OFFERS,x
        inx
        stx GK
        cpx #3
        bne @k
        rts
.endproc

card_col0:  .word 1, 11, 21
card_cols:  .word 2*2, 12*2, 22*2       ; interior text column (byte offset)
card_iconx: .word 1*8+20, 11*8+20, 21*8+20
rar_pal:    .byte $08, $14, $18          ; BG1 attr high byte: palette 2 / 5 / 6
rar_attr:   .byte ATTR_W, ATTR_G, ATTR_P

; draw the three card frames into the BG1 shadow (selected card in gold)
.proc draw_cards
        .a8
        .i16
        ldx #$0000
        stx GK
@c:     A16
        lda GK
        asl
        tax
        lda card_col0,x
        sta DC_C0
        A8
        ldx GK
        lda OFFERS,x
        A16
        and #$00FF
        tay
        A8
        lda perk_rar,y
        A16
        and #$00FF
        tay
        A8
        lda rar_pal,y
        sta DC_FR
        lda #$08
        sta DC_IN
        lda GK
        cmp CURSOR
        bne :+
        lda #$10                ; palette 4: gold
        sta DC_FR
        sta DC_IN
:       ldx #5
        stx DC_R
@r:     ldx #$0000
        stx DC_C
@cl:    A16
        lda DC_R
        asl
        asl
        asl
        asl
        asl
        clc
        adc DC_C0
        clc
        adc DC_C
        asl
        tax
        A8
        lda DC_R
        cmp #5
        beq @b
        cmp #21
        beq @b
        lda DC_C
        beq @b
        cmp #8
        beq @b
        lda #0
        sta f:BG1MAP,x
        lda DC_IN
        sta f:BG1MAP+1,x
        bra @nx
@b:     lda #170
        sta f:BG1MAP,x
        lda DC_FR
        sta f:BG1MAP+1,x
@nx:    inc DC_C
        lda DC_C
        cmp #9
        bne @cl
        inc DC_R
        lda DC_R
        cmp #22
        bne @r
        A16
        inc GK
        lda GK
        cmp #3
        A8
        beq :+
        jmp @c
:       lda #$01
        sta bg1_dirty
        rts
.endproc

; text for card GK
.proc card_text
        .a8
        .i16
        A16
        lda GK
        asl
        tax
        lda card_cols,x
        sta CT_COL
        A8
        ldx GK
        lda OFFERS,x
        sta CT_P
        stz CT_P+1
        sta M_A
        lda #10
        sta M_B
        jsr mul8
        ; name (row 11)
        A16
        ldy M_RES
        lda perk_txt,y
        sta str_ptr
        lda CT_COL
        clc
        adc #(11*64)
        tax
        A8
        lda #ATTR_Y
        sta text_attr
        jsr print
        ; description rows 13..16
        ldx #1
        stx CT_L
@l:     A16
        lda CT_L
        asl
        clc
        adc M_RES
        tay
        lda perk_txt,y
        sta str_ptr
        lda CT_L
        clc
        adc #12
        xba
        lsr
        lsr
        clc
        adc CT_COL
        tax
        A8
        lda #ATTR_W
        sta text_attr
        jsr print
        A16
        inc CT_L
        lda CT_L
        cmp #5
        A8
        bne @l
        ; owned count (row 18)
        ldy CT_P
        lda PERKS,y
        beq @rar
        A16
        lda CT_COL
        clc
        adc #(18*64)
        tax
        A8
        ldy #.loword(s_own)
        sty str_ptr
        lda #ATTR_G
        sta text_attr
        jsr print
        ldy CT_P
        lda PERKS,y
        jsr put_digit
@rar:   ; rarity (row 20)
        ldy CT_P
        lda perk_rar,y
        A16
        and #$00FF
        tay
        asl
        tax
        lda rar_str,x
        sta str_ptr
        lda CT_COL
        clc
        adc #(20*64)
        tax
        A8
        lda rar_attr,y
        sta text_attr
        jmp print
.endproc

.proc all_card_text
        .a8
        .i16
        ldx #$0000
        stx GK
@ct:    jsr card_text
        A16
        inc GK
        lda GK
        cmp #3
        A8
        bne @ct
        lda #27
        jsr clear_row
        lda REROLLS
        beq :+
        PRINT 27, 8, s_reroll, ATTR_G
:       rts
.endproc

.proc enter_draft
        .a8
        .i16
        lda #$80
        sta INIDISP
        stz NMITIMEN
        jsr music_stop
        ldx #$0000
        stx CURSOR
        ldx #40
        stx timer
        stz SHAKE_T
        stz FL_R
        stz FL_G
        stz FL_B
        jsr juice_update
        jsr gen_offers
        lda #1
        sta REROLLS
        A16
        lda #(85 | $0800)
        ldx #$0000
@f:     sta f:BG1MAP,x
        inx
        inx
        cpx #2048
        bne @f
        A8
        jsr draw_cards
        jsr clear_bg3
        PRINT 1, 9, s_choose, ATTR_Y
        PRINT 2, 10, s_forstage, ATTR_W
        ldx #(2*64 + 20*2)
        lda stage
        jsr put_dec2
        jsr all_card_text
        lda P_TOTAL
        beq :+
        PRINT 23, 11, s_yours, ATTR_W
        ldx #(24*64)
        jsr draw_owned
:       PRINT 26, 3, s_dhelp, ATTR_W
        jsr upload_bg1
        jsr upload_bg3
        lda #ST_DRAFT
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
        SFX 2, jingle_draft
        rts
.endproc

.proc st_draft
        .a8
        .i16
        A16
        lda timer
        beq :+
        dec timer
:       lda joy_new
        and #$0200              ; left
        A8
        beq @nl
        lda CURSOR
        bne :+
        lda #3
:       dec a
        sta CURSOR
        jsr draw_cards
        SFX 0, sfx_tick
@nl:    A16
        lda joy_new
        and #$0100              ; right
        A8
        beq @nr
        lda CURSOR
        inc a
        cmp #3
        bcc :+
        lda #0
:       sta CURSOR
        jsr draw_cards
        SFX 0, sfx_tick
@nr:    A16
        lda joy_new
        and #$2000              ; select: reroll
        A8
        beq @nrr
        lda REROLLS
        beq @nrr
        dec REROLLS
        jsr gen_offers
        jsr draw_cards
        ldx #11
        stx loopi
:       lda loopi
        jsr clear_row
        inc loopi
        lda loopi
        cmp #21
        bne :-
        jsr all_card_text
        SFX 0, sfx_item
@nrr:   A16
        lda timer
        bne @r
        lda joy_new
        and #$D080              ; B, Y, Start or A takes the perk
        beq @r
        A8
        ldx CURSOR
        lda OFFERS,x
        A16
        and #$00FF
        tay
        A8
        lda PERKS,y
        inc a
        sta PERKS,y
        inc P_TOTAL
        cpy #P_PHOENIX
        bne :+
        lda lives
        cmp #9
        bcs :+
        inc lives
:       cpy #P_GLASS
        bne :+
        lda lives
        cmp #2
        bcc :+
        dec lives
:       lda #ST_READY
        jsr goto_state
        SFX 2, jingle_start
        rts
@r:     A8
        rts
.endproc

.proc draft_oam
        .a8
        .i16
        ldx #$0000
        stx loopi
@l:     A16
        lda loopi
        sta spr_slot
        asl
        tax
        lda card_iconx,x
        sta spr_x
        A8
        ldx loopi
        lda OFFERS,x
        pha
        and #$03
        asl
        asl
        sta tmp0
        pla
        lsr
        lsr
        asl
        asl
        asl
        asl
        asl
        asl
        ora tmp0
        sta spr_tile
        lda #47
        sta spr_y
        lda loopi
        cmp CURSOR
        bne :+
        lda nmi_count           ; selected icon bobs
        and #$10
        beq :+
        lda #45
        sta spr_y
:       lda #$39                ; priority 3, palette 4, second name table
        sta spr_attr
        lda #1
        sta spr_big
        jsr put_sprite
        A16
        inc loopi
        lda loopi
        cmp #3
        A8
        bne @l
        rts
.endproc


; =============================================================================
;  Explicit state machines (modelled in spec/GameFSM.tla)
; =============================================================================
;  Game flow                          Player mode (only during a stage)
;    BOOT  -> TITLE                     EDGE    -> DRAW     cut starts
;    TITLE -> DRAFT     start           DRAW    -> RETRACT  cut button released
;    DRAFT -> READY     perk taken      RETRACT -> DRAW     pressed again
;    READY -> PLAY      timer           RETRACT -> EDGE     trail fully retracted
;    PLAY  -> PAUSE     start           DRAW    -> EDGE     cut closed (filled)
;    PAUSE -> PLAY      start           any     -> EDGE     trail wiped (hit)
;    PLAY  -> DYING     hit, no AEGIS
;    PLAY  -> CLEAR     goal reached    invariant: pmode = EDGE <=> trail_len = 0
;    DYING -> PLAY      lives left
;    DYING -> OVER      no lives        A handler that changes state must return
;    CLEAR -> DRAFT     timer           straight away (st_play re-checks `state`
;    OVER  -> TITLE     timer / start   after the player moves).
;
;  `state` changes only after the target's entry action has finished, so a
;  multi-frame entry (forced-blank loads) is never observed half-done.
;
;  goto_state / set_pmode are the only writers of `state` / `pmode` (besides
;  the boot value and the per-stage reset). An illegal transition is still
;  taken, so the game keeps running, but it is counted in FSM_ERRS with the
;  offending pair, which the test harness asserts stays at zero.

bitw_tab:   .word $0001, $0002, $0004, $0008, $0010, $0020, $0040, $0080, $0100

; bit mask of the states each state may be entered from (index = target)
fsm_allow:
        .word (1 << ST_BOOT) | (1 << ST_OVER)                 ; TITLE
        .word (1 << ST_DRAFT)                              ; READY
        .word (1 << ST_READY) | (1 << ST_PAUSE) | (1 << ST_DYING) ; PLAY
        .word (1 << ST_PLAY)                               ; DYING
        .word (1 << ST_PLAY)                               ; CLEAR
        .word (1 << ST_DYING)                              ; OVER
        .word (1 << ST_TITLE) | (1 << ST_CLEAR)               ; DRAFT
        .word (1 << ST_PLAY)                               ; PAUSE
; entry actions (index = target)
fsm_enter:
        .word enter_title, load_stage, enter_play, enter_dying
        .word enter_clear, enter_gameover, enter_draft, enter_pause

pm_allow:
        .word (1 << PM_EDGE) | (1 << PM_DRAW) | (1 << PM_RETRACT) ; -> EDGE
        .word (1 << PM_EDGE) | (1 << PM_RETRACT)               ; -> DRAW
        .word (1 << PM_DRAW)                                ; -> RETRACT

; A = target state. Validates, switches, runs the entry action.
.proc goto_state
        .a8
        .i16
        sta FSM_NEW
        stz FSM_NEW+1
        A16
        lda state
        and #$00FF
        asl
        tax
        lda bitw_tab,x
        sta FSM_TMP
        lda FSM_NEW
        asl
        tax
        lda fsm_allow,x
        and FSM_TMP
        A8
        bne @ok
        lda #1
        sta FSM_KIND
        lda state
        jsr fsm_fault
@ok:    lda FSM_NEW
        pha
        A16
        and #$00FF
        asl
        tax
        A8
        jsr (fsm_enter,x)       ; entry action runs in the old state...
        pla
        sta state               ; ...and the new state is committed only
        rts                     ; once it is fully set up
.endproc

; A = target player mode
.proc set_pmode
        .a8
        .i16
        sta FSM_NEW
        stz FSM_NEW+1
        A16
        lda pmode
        and #$00FF
        asl
        tax
        lda bitw_tab,x
        sta FSM_TMP
        lda FSM_NEW
        asl
        tax
        lda pm_allow,x
        and FSM_TMP
        A8
        bne @ok
        lda #2
        sta FSM_KIND
        lda pmode
        jsr fsm_fault
@ok:    lda FSM_NEW
        sta pmode
        rts
.endproc

; A = "from" value; FSM_KIND / FSM_NEW already set
.proc fsm_fault
        .a8
        .i16
        sta FSM_FROM
        lda FSM_NEW
        sta FSM_TO
        lda FSM_ERRS
        cmp #$FF
        beq :+
        inc FSM_ERRS
:       rts
.endproc

; once per frame: pmode = EDGE <=> trail_len = 0 while a stage is running
.proc fsm_check
        .a8
        .i16
        lda state
        cmp #ST_TITLE
        beq @ok
        cmp #ST_DRAFT
        beq @ok
        cmp #ST_OVER
        beq @ok
        A16
        lda trail_len
        A8
        beq @empty
        lda pmode               ; trail exists: must be cutting
        bne @ok
        bra @bad
@empty: lda pmode               ; no trail: must be on the edge
        beq @ok
@bad:   lda #3
        sta FSM_KIND
        lda pmode
        sta FSM_NEW
        lda state
        jsr fsm_fault
@ok:    rts
.endproc

.proc enter_play
        .a8
        .i16
        lda #13
        jsr clear_row
        lda #14
        jsr clear_row
        lda #15
        jsr clear_row
        jmp music_start
.endproc

.proc enter_pause
        .a8
        .i16
        PRINT 14, 13, s_paused, ATTR_Y
        jmp music_stop
.endproc

.proc st_pause
        .a8
        .i16
        A16
        lda joy_new
        and #BTN_START
        A8
        beq :+
        lda #ST_PLAY
        jmp goto_state
:       rts
.endproc


; =============================================================================
;  Benchmark build (make bench): times score_claim on the vectors shared with
;  the C trial in experiments/c-trial, results at $7E8000 (16 bytes each).
; =============================================================================
.ifdef BENCH

.proc run_bench
        .a8
        .i16
        lda #$80
        sta NMITIMEN            ; NMI only counts frames (frame_ready stays 0)
        ldx #$0000
        stx B_I
        stx B_O
@next:  ldx B_I
        A16
        lda bench_vectors,x
        sta newly
        lda bench_vectors+4,x
        sta JACKMULT
        A8
        lda bench_vectors+2,x
        sta CHAIN
        lda bench_vectors+3,x
        sta KILLS
        lda bench_vectors+6,x
        sta P_TOTAL
        ldy #$0000
:       lda bench_vectors+8,x
        sta PERKS,y
        inx
        iny
        cpy #16
        bne :-
        ldx #$0000
        stx freeze
        ldx B_O
        STAMP 6
        jsr score_claim
        ldx B_O
        STAMP 11
        A16
        lda MULT
        sta f:BENCH_OUT,x
        lda PROD
        sta f:BENCH_OUT+2,x
        lda PROD+2
        sta f:BENCH_OUT+4,x
        lda B_O
        clc
        adc #24
        sta B_O
        lda B_I
        clc
        adc #24
        sta B_I
        cmp #(BENCH_N * 24)
        A8
        beq :+
        jmp @next
:
        lda #1
        sta f:BENCH_OUT+$0FFF   ; done
:       bra :-
.endproc

.segment "RODATA"
bench_vectors: .incbin "vectors.bin"
.segment "CODE"
.endif

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
        .byte $C4, $00                  ; mov $00,a      last := port0
        .byte $8F, $A5, $F5             ; mov $f5,#$a5   READY (after last!)
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
        .res $0300 - $0200 - 33, 0
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
        .word RGB(0,0,0), RGB(130,255,150), RGB(0,30,0), RGB(200,255,200)
        .word RGB(0,0,0), RGB(255,140,230), RGB(40,0,30), RGB(255,200,240)
        .word RGB(0,0,0), RGB(255,150,40), RGB(50,20,0), RGB(255,220,120)
bg1_pal:
        .word RGB(0,0,0), RGB(14,18,52), RGB(52,64,130), RGB(210,240,255)
        .word RGB(255,220,40), RGB(90,130,200), 0, 0
        .word 0, 0, 0, 0, 0, 0, 0, 0

title_map: .incbin "title.map"

s_score:  .asciiz "SCORE"
s_stage:  .asciiz "STAGE"
s_area:   .asciiz "AREA   %/  %"
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


; ---- perks
perk_max:    .byte 9, 5, 3, 5, 5, 1, 3, 3, 3, 9, 2, 5, 1, 3, 5, 3
perk_rar:    .byte 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0, 2, 2, 1, 0, 1
perk_weight: .byte 4, 4, 2, 4, 4, 4, 2, 4, 2, 2, 4, 1, 1, 2, 4, 2
rar_str:     .word s_common, s_special, s_rare
perk_txt:
        .word pt0_0, pt0_1, pt0_2, pt0_3, s_empty
        .word pt1_0, pt1_1, pt1_2, pt1_3, pt1_4
        .word pt2_0, pt2_1, pt2_2, pt2_3, pt2_4
        .word pt3_0, pt3_1, pt3_2, pt3_3, pt3_4
        .word pt4_0, pt4_1, pt4_2, pt4_3, pt4_4
        .word pt5_0, pt5_1, pt5_2, s_empty, s_empty
        .word pt6_0, pt6_1, pt6_2, pt6_3, pt6_4
        .word pt7_0, pt7_1, pt7_2, pt7_3, pt7_4
        .word pt8_0, pt8_1, pt8_2, pt8_3, pt8_4
        .word pt9_0, pt9_1, s_empty, s_empty, s_empty
        .word pt10_0, pt10_1, pt10_2, pt10_3, pt10_4
        .word pt11_0, pt11_1, pt11_2, pt11_3, pt11_4
        .word pt12_0, pt12_1, pt12_2, pt12_3, s_empty
        .word pt13_0, pt13_1, pt13_2, s_empty, s_empty
        .word pt14_0, pt14_1, pt14_2, pt14_3, pt14_4
        .word pt15_0, pt15_1, pt15_2, pt15_3, s_empty
pt0_0: .asciiz "GREED"
pt0_1: .asciiz "+2 MULT"
pt0_2: .asciiz "EVERY"
pt0_3: .asciiz "CLAIM"
pt1_0: .asciiz "CHAIN"
pt1_1: .asciiz "CHAIN"
pt1_2: .asciiz "LINKS"
pt1_3: .asciiz "+1 MULT"
pt1_4: .asciiz "MORE"
pt2_0: .asciiz "TITAN"
pt2_1: .asciiz "X2 MULT"
pt2_2: .asciiz "ON BIG"
pt2_3: .asciiz "CLAIMS"
pt2_4: .asciiz "(150+)"
pt3_0: .asciiz "SNIPER"
pt3_1: .asciiz "+6 MULT"
pt3_2: .asciiz "ON TINY"
pt3_3: .asciiz "CLAIMS"
pt3_4: .asciiz "(<40)"
pt4_0: .asciiz "HUNTER"
pt4_1: .asciiz "+3 MULT"
pt4_2: .asciiz "PER"
pt4_3: .asciiz "SHARD"
pt4_4: .asciiz "KILLED"
pt5_0: .asciiz "SWIFT"
pt5_1: .asciiz "MOVE"
pt5_2: .asciiz "FASTER"
pt6_0: .asciiz "AEGIS"
pt6_1: .asciiz "BLOCK"
pt6_2: .asciiz "1 HIT"
pt6_3: .asciiz "EACH"
pt6_4: .asciiz "STAGE"
pt7_0: .asciiz "STASIS"
pt7_1: .asciiz "CLAIMS"
pt7_2: .asciiz "FREEZE"
pt7_3: .asciiz "FOES"
pt7_4: .asciiz "1.5 SEC"
pt8_0: .asciiz "CHRONO"
pt8_1: .asciiz "FOES"
pt8_2: .asciiz "MOVE"
pt8_3: .asciiz "20%"
pt8_4: .asciiz "SLOWER"
pt9_0: .asciiz "PHOENIX"
pt9_1: .asciiz "+1 LIFE"
pt10_0: .asciiz "LUCKY"
pt10_1: .asciiz "+1"
pt10_2: .asciiz "CAPSULE"
pt10_3: .asciiz "EACH"
pt10_4: .asciiz "STAGE"
pt11_0: .asciiz "PRISM"
pt11_1: .asciiz "+1 MULT"
pt11_2: .asciiz "PER"
pt11_3: .asciiz "PERK"
pt11_4: .asciiz "OWNED"
pt12_0: .asciiz "GLASS"
pt12_1: .asciiz "X3 MULT"
pt12_2: .asciiz "BUT"
pt12_3: .asciiz "-1 LIFE"
pt13_0: .asciiz "QUOTA"
pt13_1: .asciiz "GOAL"
pt13_2: .asciiz "-5%"
pt14_0: .asciiz "JACKPOT"
pt14_1: .asciiz "CAPSULE"
pt14_2: .asciiz "GIVES"
pt14_3: .asciiz "+4 MULT"
pt14_4: .asciiz "(STAGE)"
pt15_0: .asciiz "MIDAS"
pt15_1: .asciiz "STAGE"
pt15_2: .asciiz "BONUS"
pt15_3: .asciiz "X2"
s_empty:   .asciiz ""
s_common:  .asciiz "COMMON"
s_special: .asciiz "SPECIAL"
s_rare:    .asciiz "RARE"
s_own:     .asciiz "OWN "
s_chain:   .asciiz "CHAIN"
s_x:       .asciiz " X "
s_eq:      .asciiz " = +"
s_aegis:   .asciiz "AEGIS BLOCKED THE HIT!"
s_choose:  .asciiz "CHOOSE A PERK"
s_forstage:.asciiz "FOR STAGE"
s_yours:   .asciiz "YOUR PERKS"
s_dhelp:   .asciiz "LEFT/RIGHT CHOOSE  B TAKE"
s_reroll:  .asciiz "SELECT: REROLL"
s_broken:  .asciiz "CHAIN BROKEN!"

card_pals:
        .word 0, RGB(70,40,6), RGB(160,110,30), RGB(255,230,110), RGB(255,220,40), RGB(215,150,40), 0, 0
        .word 0, 0, 0, 0, 0, 0, 0, 0
        .word 0, RGB(14,18,52), RGB(52,64,130), RGB(130,255,150), RGB(255,220,40), RGB(60,170,90), 0, 0
        .word 0, 0, 0, 0, 0, 0, 0, 0
        .word 0, RGB(14,18,52), RGB(52,64,130), RGB(255,130,230), RGB(255,220,40), RGB(190,60,170), 0, 0
        .word 0, 0, 0, 0, 0, 0, 0, 0

sfx_tick:
        NOTE 2, 3211, $28
        .byte 0
jingle_draft:
        NOTE 5, 3211, $40
        NOTE 5, 4288, $40
        NOTE 10, 6423, $40
        NOTE 10, 6423, $18
        .byte 0

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
icon_tiles: .incbin "icons.bin"
icon_pal:   .incbin "iconpal.bin"
mini_tiles: .incbin "minis.bin"

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
