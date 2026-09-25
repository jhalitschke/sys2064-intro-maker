#importonce
// ---------------------------------------------------------------------------
// memmap.asm - ALL addresses, memory boundaries and hardware registers.
// No other file may contain raw addresses.
// ---------------------------------------------------------------------------

// ---- CPU port ------------------------------------------------------------
.label CPU_PORT          = $01
.const CPU_IO_ONLY       = $35      // RAM + I/O, no BASIC/KERNAL
.const CPU_CHARROM       = $33      // BASIC + KERNAL + char ROM at $d000
.const CPU_DEFAULT       = $37      // BASIC + KERNAL + I/O

// ---- Zero page: runtime ($02-$1f) -----------------------------------------
.const ZP_RT_START       = $02
.label rt_sptr           = $02      // 2: scroll text pointer
.label rt_xscroll        = $04
.label rt_speed          = $05
.label rt_pause          = $06
.label rt_wrapped        = $07
.label rt_bar_phase      = $08
.label rt_spr_px         = $09
.label rt_spr_py         = $0a
.label rt_cyc_phase      = $0b
.label rt_cyc_div        = $0c
.label rt_exit_req       = $0d
.label rt_msb            = $0e
.label rt_t0             = $0f
.label rt_t1             = $10
.label rt_t2             = $11
.label rt_t3             = $12
.label rt_ptr            = $13      // 2
.label rt_ptr2           = $15      // 2
.label rt_px             = $17      // 2: title x in the band
.label rt_py             = $19      // title y in the band
.label rt_mv_phase       = $1a
.label rt_title_d011     = $1b      // applied in IRQ TOP
.label rt_title_d016     = $1c
.label rt_cur_col        = $1d      // drawn title position ($ff = none)
.label rt_cur_row        = $1e
.label rt_mv_tmp         = $1f
.const ZP_RT_END         = $20      // first unused byte
.errorif ZP_RT_END > $20, "runtime zero page overflow"

// ---- Zero page: editor ($20-$3f) ------------------------------------------
.const ZP_ED_START       = $20
.label ed_scr            = $20      // 2: screen pointer
.label ed_colp           = $22      // 2: colour RAM pointer
.label ed_str            = $24      // 2: string pointer
.label ed_ptr            = $26      // 2: general pointer
.label ed_ptr2           = $28      // 2: general pointer
.label ed_color          = $2a      // current print colour
.label ed_t0             = $2b
.label ed_t1             = $2c
.label ed_t2             = $2d
.label ed_t3             = $2e
.label ed_num            = $2f      // 2: number to print
.label ed_digit          = $31
.label ed_lead           = $32
.label ed_n_count        = $33
.label ed_n_index        = $34
.const ZP_ED_END         = $35
.errorif ZP_ED_END > $40, "editor zero page overflow"

// KERNAL zero page / system variables used by the editor
.label KERNAL_DEV        = $ba      // last used device
.label KERNAL_NDX        = $c6      // keyboard buffer length
.label KERNAL_BLNSW      = $cc      // cursor blink switch (0 = blink)
.label KERNAL_JIFFY_LO   = $a2
.label SAVE_PTR          = $fb      // 2: start pointer for SAVE

// ---- Screen ---------------------------------------------------------------
.label SCREEN            = $0400
.const SCREEN_SIZE       = 1000
.const SCREEN_COLS       = 40
.const SCREEN_ROWS       = 25
.label SPRITE_PTRS       = $07f8
.label COLRAM            = $d800

// ---- Program image --------------------------------------------------------
.label BASIC_START       = $0801
.label ENTRY_JMP         = $0810    // JMP <entry>, operand is patched
.label ENTRY_OPERAND     = ENTRY_JMP + 1
.const BASIC_SYS_ADDR    = ENTRY_JMP
.label RT_CODE           = $0813
.label RT_CODE_END       = $0fc0    // exclusive
.label SPRITE_DATA       = $0fc0    // biggest star frame (built at start)
.const SPRITE_PTR        = SPRITE_DATA / 64
.label STAR_TAPE         = $0340    // 3 smaller star frames in the tape buffer
.const STAR_TAPE_BLOCKS  = 3        // (unused while the runtime runs)
.errorif (STAR_TAPE & 63) != 0, "star frames must be sprite block aligned"
.errorif STAR_TAPE + STAR_TAPE_BLOCKS * 64 > SCREEN, "star frames reach the screen"
.label SID_START         = $1000
.label SID_END           = $2000    // exclusive, max 4 KB
.label FONT              = $2000
.const FONT_USED_SIZE    = $0200    // chars $00-$3f
.label FONT_END          = $2800    // exclusive
.label CHAR_ROM          = $d000    // visible with CPU_CHARROM
.label CONFIG            = $2800
.label CONFIG_END        = $2900
// runtime work area behind the config block (same page, saved with it)
.label RT_WORK           = $28b0
.label rt_gw             = RT_WORK + $00   // glyph width/height in chars
.label rt_gh             = RT_WORK + $01
.label rt_mc             = RT_WORK + $02   // multicolour title
.label rt_len            = RT_WORK + $03   // 2: glyphs per title line
.label rt_off            = RT_WORK + $05   // 2: column offset per line
.label rt_lines          = RT_WORK + $07
.label rt_maxlen         = RT_WORK + $08
.label rt_rows           = RT_WORK + $09   // text rows of the title
.label rt_rx             = RT_WORK + $0a   // 2: x range in pixels
.label rt_ry             = RT_WORK + $0c   // y range in pixels
.label rt_bx             = RT_WORK + $0d   // 2: bumper x
.label rt_bdir           = RT_WORK + $0f
.label rt_cyc_ext        = RT_WORK + $10   // CYC_EXT_LEN colours
.const CYC_EXT_LEN       = 56              // 16 + 40
.label rt_frame          = RT_WORK + $48   // set by IRQ BOTTOM
.label rt_pending        = RT_WORK + $49   // next title position ready
.label rt_next_col       = RT_WORK + $4a
.label rt_next_row       = RT_WORK + $4b
.label rt_next_d011      = RT_WORK + $4c
.label rt_next_d016      = RT_WORK + $4d
.label rt_wchars         = RT_WORK + $4e   // title width in chars
.label rt_star_count     = RT_WORK + $4f   // star animation frame counter
.label RT_WORK_END       = RT_WORK + $50
.errorif rt_frame < rt_cyc_ext + CYC_EXT_LEN, "runtime work area overlap"
.errorif RT_WORK_END > CONFIG_END, "runtime work area overflow"
.label RT_TABLES         = $2900
.label RT_TABLES_END     = $2c00
.label TEXT              = $2c00
.label VIC_IDLE_BYTE     = $3fff    // must be $00 (FLD gap shows it)
.label TEXT_END          = VIC_IDLE_BYTE // exclusive, incl. $ff terminator
.const TEXT_MAX          = TEXT_END - TEXT - 1  // 5118 characters
.label EDITOR_CODE       = $4000
.label EDITOR_END        = $6800
.label CATALOG           = $6800
.label CATALOG_END       = $7000
.label FILE_BUF          = $7000    // files / directory read from disk
.label FILE_BUF_END      = $9000
.label DIR_NAMES         = $9000    // DIR_MAX x 16 byte names (PETSCII)
.label DIR_LENS          = $9900    // DIR_MAX name lengths
.label ED_VARS           = $9a00    // editor variables
.label ED_VARS_END       = $9c00
.label spread_lo         = $9c00    // ROM 2X2 bit spreading tables
.label spread_hi         = $9d00
.label spread_lo_s       = $9e00
.label spread_hi_s       = $9f00
.label ED_WORK_END       = $a000    // BASIC ROM above

.errorif DIR_NAMES < FILE_BUF_END, "directory table overlaps the file buffer"

.errorif TEXT_MAX != 5118, "text size must be 5118"
.errorif SPRITE_DATA + 64 > SID_START, "sprite data overlaps SID"
.errorif CONFIG < FONT + FONT_USED_SIZE, "config overlaps font"
.errorif (RT_TABLES & $ff) != 0, "runtime tables must be page aligned"

// ---- Screen layout (runtime) ----------------------------------------------
.const TITLE_LEN         = 80
.const TITLE_LINE_LEN    = 40
// Title band: text rows 0-8, first line 48 + YSCROLL. Moving titles use
// YSCROLL/XSCROLL for the fine position and screen rows for the coarse one.
.const BAND_FIRST_LINE   = $30
.const BAND_ROWS         = 9
.const BAND_LINES        = BAND_ROWS * 8            // 72
.label BAND_COLOR        = COLRAM
.const BIG_TILE_FIRST    = $40
.label BIG_TILES         = FONT + BIG_TILE_FIRST * 8   // big title font tiles
.const BIG_TILE_MAX      = $100 - BIG_TILE_FIRST        // 192
.const SCROLL_ROW        = 13
.label SCROLL_SCREEN     = SCREEN + SCROLL_ROW * SCREEN_COLS   // $0608
.label SCROLL_COLOR      = COLRAM + SCROLL_ROW * SCREEN_COLS   // $da08
.errorif SCROLL_SCREEN != $0608, "scroller must be at $0608"

// ---- Raster lines (PAL) ---------------------------------------------------
.const PAL_LINES         = 312
.const PAL_CYCLES        = 63
.const IRQ_TOP_LINE      = $10
.const IRQ_MID_LINE      = 125      // after the title band, see irq_mid
.const MID_KEEP_YSCROLL  = 6        // title YSCROLL >= 6: row 9 still ahead
.const IRQ_BARS_LINE     = $80
.errorif BAND_FIRST_LINE + BAND_LINES > IRQ_MID_LINE + 1, "title band reaches the MID IRQ"
.const IRQ_SCROLL_LINE   = $e8
.const IRQ_BOTTOM_LINE   = $f8
.const ED_IRQ_LINE       = $fa
.const FLD_FIRST_LINE    = 131
.const FLD_LINES         = 80
.const FLD_LAST_LINE     = FLD_FIRST_LINE + FLD_LINES - 1        // 210
.const BAR_HEIGHT        = 15
.const BAR_COUNT         = 3
.const BAR_POS_MAX       = FLD_LINES - BAR_HEIGHT                // 65
.const SPR_Y_MIN         = 76
.const SPR_Y_MAX         = 104
.const SPR_HEIGHT        = 21
.const SPR_X_MIN         = 24
.const SPR_X_MAX         = 320
.errorif SPR_Y_MAX + SPR_HEIGHT + 1 >= IRQ_BARS_LINE - 1, "sprites reach the stable raster IRQ"
.errorif FLD_FIRST_LINE <= IRQ_BARS_LINE + 2, "FLD must start after the double IRQ"

// ---- Runtime tables ------------------------------------------------------
// Saved with the intro ($2900-$2bff): the movement sine and a second code
// segment. The other tables and the bar buffers live in RAM under the KERNAL
// (not saved, unused by the editor and by linked programs) and are built by
// runtime_start.
.label mv_sin            = RT_TABLES                // |sine| 0..127, half wave
.const SIN_LEN           = 128                      // phases per period
.label RT_CODE2          = RT_TABLES + SIN_LEN / 2
.label RT_CODE2_END      = RT_TABLES_END
.label RT_RAM            = $e000
.label border_buf        = RT_RAM + $00
.label bg_buf            = RT_RAM + $50
.label fld_tab           = RT_RAM + $a0
.label bar_sin           = RT_RAM + $100
.label spr_x2            = RT_RAM + $180            // sprite x / 2
.label spr_y             = RT_RAM + $200
.label TITLE_IMG         = RT_RAM + $280            // title drawn at row/col 0
.const TITLE_IMG_SIZE    = BAND_ROWS * SCREEN_COLS
.label rt_presets        = TITLE_IMG + TITLE_IMG_SIZE // 8 x 15 bar colours
.label RT_ZP_SAVE        = rt_presets + 8 * 15      // BASIC zero page at start
.label RT_RAM_END        = RT_ZP_SAVE + ZP_RT_END - ZP_RT_START
.errorif (RT_RAM & $ff) != 0, "RT_RAM must be page aligned"
.errorif (border_buf >> 8) != ((border_buf + FLD_LINES - 1) >> 8), "border_buf crosses a page"
.errorif (bg_buf >> 8) != ((bg_buf + FLD_LINES - 1) >> 8), "bg_buf crosses a page"
.errorif (fld_tab >> 8) != ((fld_tab + FLD_LINES - 1) >> 8), "fld_tab crosses a page"
.errorif bg_buf < border_buf + FLD_LINES, "bar buffers overlap"
.errorif fld_tab < bg_buf + FLD_LINES, "bar buffers overlap"
.errorif RT_RAM_END > HW_NMI_VEC, "runtime RAM tables reach the vectors"

// ---- Editor variables ($6800-$6fff) ---------------------------------------
// (laid out as a virtual segment in editor.asm)

// ---- VIC-II ---------------------------------------------------------------
.label VIC_SPR0_X        = $d000
.label VIC_SPR0_Y        = $d001
.label VIC_SPR_XMSB      = $d010
.label VIC_CTRL1         = $d011
.label VIC_RASTER        = $d012
.label VIC_SPR_ENABLE    = $d015
.label VIC_CTRL2         = $d016
.label VIC_SPR_YEXP      = $d017
.label VIC_MEMPTR        = $d018
.label VIC_IRQ_FLAG      = $d019
.label VIC_IRQ_ENABLE    = $d01a
.label VIC_SPR_PRIO      = $d01b
.label VIC_SPR_MC        = $d01c
.label VIC_SPR_XEXP      = $d01d
.label VIC_BORDER        = $d020
.label VIC_BG            = $d021
.label VIC_BG1           = $d022
.label VIC_BG2           = $d023
.label VIC_SPR0_COL      = $d027
.const VIC_IRQ_RASTER    = $01
.const VIC_IRQ_ACK_ALL   = $ff

.const RT_D011           = $1b      // screen on, 25 rows, YSCROLL 3
.const RT_D016           = $c8      // 40 columns, XSCROLL 0
.const RT_D016_38        = $c0      // 38 columns, OR xscroll
.const RT_D018           = $18      // screen $0400, charset $2000
.const ED_D011           = $1b
.const ED_D016           = $c8
.const ED_D018           = $14      // screen $0400, ROM upper case
.const D011_BASE         = $18      // DEN + RSEL, YSCROLL 0
.const FLD_PRE_D011      = D011_BASE | ((FLD_FIRST_LINE + 1) & 7)

// ---- SID ------------------------------------------------------------------
.label SID_BASE          = $d400
.label SID_V1_FREQ_LO    = $d400
.label SID_V1_FREQ_HI    = $d401
.label SID_V1_PW_LO      = $d402
.label SID_V1_PW_HI      = $d403
.label SID_V1_CTRL       = $d404
.label SID_V1_AD         = $d405
.label SID_V1_SR         = $d406
.label SID_VOLUME        = $d418
.const SID_REGS          = $19

// ---- CIA ------------------------------------------------------------------
.label CIA1_PRA          = $dc00
.label CIA1_PRB          = $dc01
.label CIA1_ICR          = $dc0d
.label CIA2_ICR          = $dd0d
.const CIA_IRQ_ALL_OFF   = $7f
.const CIA_IRQ_TIMER_A   = $81
.const KEY_ROW_SPACE     = $7f      // select row 7
.const KEY_BIT_SPACE     = $10      // PRB bit 4

// ---- Vectors --------------------------------------------------------------
.label HW_NMI_VEC        = $fffa
.label HW_IRQ_VEC        = $fffe
.label KERNAL_IRQ_VEC    = $0314

// ---- KERNAL ---------------------------------------------------------------
.label KERNAL_IRQ_EXIT   = $ea31
.label BASIC_RUN_INIT    = $a659    // RUN: reset text pointer + CLR
.label BASIC_NEWSTT      = $a7ae    // interpreter loop
.label VARTAB            = $2d      // end of the BASIC program
.label CINT              = $ff81
.label IOINIT            = $ff84
.label RESTOR            = $ff8a
.label VERIFY_END        = $ae      // 2: end address after LOAD/VERIFY
// linked program: mover in the tape buffer, parameters in zero page
.label MOVER_ADDR        = $033c
.label MV_LEN            = $06      // = cfg_link_len .. cfg_link_src copy
.label MV_DEST           = $08
.label MV_START          = $0a
.label MV_SRC            = $0c
.label MV_S              = $02      // 2: source pointer
.label MV_D              = $04      // 2: destination pointer
.label LINK_DEST_MIN     = $0400    // programs must not load below
.label LINK_END_MAX      = $d000    // nor reach the I/O area
.label LINK_MOVER        = EDITOR_CODE  // saved file: intro up to $3fff,
.const MOVER_SIZE_M      = 176
.label LINK_SRC          = LINK_MOVER + MOVER_SIZE_M  // mover, program
.errorif LINK_MOVER != VIC_IDLE_BYTE + 1, "linked data follows $3fff"
.label KERNAL_RESET      = $fce2
.label SETMSG            = $ff90
.label SETLFS            = $ffba
.label SETNAM            = $ffbd
.label OPEN              = $ffc0
.label CLOSE             = $ffc3
.label CHKIN             = $ffc6
.label CLRCHN            = $ffcc
.label CHKOUT            = $ffc9
.label CHROUT            = $ffd2
.label CHRIN             = $ffcf
.label LOAD              = $ffd5
.label SAVE              = $ffd8
.label GETIN             = $ffe4
.label READST            = $ffb7
