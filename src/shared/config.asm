#importonce
#import "memmap.asm"
// ---------------------------------------------------------------------------
// config.asm - config block layout, flags, defaults and other constants.
// ---------------------------------------------------------------------------

// ---- Config block layout (at CONFIG) --------------------------------------
.const CFG_MAGIC         = $00      // 2: "IM"
.const CFG_VERSION       = $02
.const CFG_FLAGS         = $03
.const CFG_BORDER        = $04
.const CFG_BG            = $05
.const CFG_SCROLLCOL     = $06
.const CFG_TITLECOL      = $07
.const CFG_PRESET        = $08
.const CFG_SPEED         = $09
.const CFG_INIT          = $0a      // 2
.const CFG_PLAY          = $0c      // 2
.const CFG_SUBTUNE       = $0e
.const CFG_TITLE         = $10      // 80 screen codes
.const CFG_SIZE          = CFG_TITLE + TITLE_LEN
.errorif CONFIG + CFG_SIZE > CONFIG_END, "config block too large"

.label cfg_magic         = CONFIG + CFG_MAGIC
.label cfg_version       = CONFIG + CFG_VERSION
.label cfg_flags         = CONFIG + CFG_FLAGS
.label cfg_border        = CONFIG + CFG_BORDER
.label cfg_bg            = CONFIG + CFG_BG
.label cfg_scrollcol     = CONFIG + CFG_SCROLLCOL
.label cfg_titlecol      = CONFIG + CFG_TITLECOL
.label cfg_preset        = CONFIG + CFG_PRESET
.label cfg_speed         = CONFIG + CFG_SPEED
.label cfg_init          = CONFIG + CFG_INIT
.label cfg_play          = CONFIG + CFG_PLAY
.label cfg_subtune       = CONFIG + CFG_SUBTUNE
.label cfg_title         = CONFIG + CFG_TITLE

// ---- Flags ----------------------------------------------------------------
.const FLAG_MUSIC        = %00000001
.const FLAG_BARS         = %00000010
.const FLAG_BAR_SINE     = %00000100
.const FLAG_SPRITES      = %00001000
.const FLAG_TITLE_CYCLE  = %00010000
.const FLAG_ALL          = %00011111

// ---- Defaults -------------------------------------------------------------
.const CFG_VERSION_1     = 1
.const DEF_FLAGS         = FLAG_BARS | FLAG_BAR_SINE | FLAG_TITLE_CYCLE
.const DEF_BORDER        = 0
.const DEF_BG            = 0
.const DEF_SCROLLCOL     = 1
.const DEF_TITLECOL      = 7
.const DEF_PRESET        = 0
.const DEF_SPEED         = 2
.const DEF_INIT          = SID_START
.const DEF_PLAY          = SID_START + 3
.const DEF_SUBTUNE       = 0
.const PRESET_COUNT      = 8
.const COLOR_COUNT       = 16

// ---- Scroll text ----------------------------------------------------------
.const CTRL_SPEED1       = $f1
.const CTRL_SPEED2       = $f2
.const CTRL_SPEED4       = $f4
.const CTRL_PAUSE        = $f8
.const TEXT_END_MARK     = $ff
.const PAUSE_FRAMES      = 100
.const SC_SPACE          = $20
.const SC_MAX            = $3f      // highest printable screen code
.const SC_REVERSE        = $80
.const SC_REV_SPACE      = SC_SPACE | SC_REVERSE
.const XSCROLL_START     = 7

// ---- Title colour cycle / sprites / bars ----------------------------------
.const CYC_LEN           = 16
.const CYC_DIVIDER       = 2        // frames per phase step
.const SPR_COUNT         = 8
.const SPR_PHASE_STEP    = 16
.const SPR_X_SPEED       = 2
.const SPR_Y_SPEED       = 3
.const BAR_PHASE_STEP    = 43
.const BAR_FIXED_0       = 5
.const BAR_FIXED_1       = 32
.const BAR_FIXED_2       = 60

// ---- Catalog --------------------------------------------------------------
.const CAT_N_SIDS        = 0
.const CAT_N_FONTS       = 1
.const CAT_RECORDS       = 2
.const CAT_REC_SIZE      = 48
.const CAT_NAME          = 0
.const CAT_NAME_LEN      = 20
.const CAT_FNLEN         = 20
.const CAT_FNAME         = 21
.const CAT_INIT          = 37
.const CAT_PLAY          = 39
.const CAT_SUBTUNE       = 41
.const CAT_MAX_SIDS      = 15
.const CAT_MAX_FONTS     = 14       // + 2 built-in fonts = 16 list rows
.const FNAME_MAX         = 16

// ---- PETSCII key codes ----------------------------------------------------
.const KEY_RETURN        = $0d
.const KEY_STOP          = $03
.const KEY_DEL           = $14
.const KEY_HOME          = $13
.const KEY_CRSR_DOWN     = $11
.const KEY_CRSR_UP       = $91
.const KEY_CRSR_RIGHT    = $1d
.const KEY_CRSR_LEFT     = $9d
.const KEY_F1            = $85
.const KEY_F3            = $86
.const KEY_F5            = $87
.const KEY_F7            = $88
.const KEY_1             = $31
.const KEY_8             = $38
.const PET_FIRST         = $20      // accepted PETSCII input range
.const PET_LAST          = $5f
.const PET_LETTERS       = $40      // $40-$5f -> screen code -$40
.const PET_CR            = $0d

// ---- Editor UI ------------------------------------------------------------
.const UI_BORDER         = 11
.const UI_BG             = 0
.const UI_COL_TEXT       = 15
.const UI_COL_HEAD       = 7
.const UI_COL_KEY        = 1
.const UI_COL_STATUS     = 13
.const UI_COL_ERROR      = 10
.const UI_COL_CURSOR     = 7
.const UI_COL_FLASH      = 2
.const UI_STATUS_ROW     = 24
.const UI_HINT_ROW       = 23
.const UI_HEAD_ROW       = 0
.const UI_MENU_ROW       = 2
.const UI_VALUE_COL      = 10
.const UI_LIST_ROW       = 4
.const UI_LIST_ROWS      = 16
.const UI_LIST_COL       = 2
.const UI_TITLE_ROW      = 4        // title editor rows 4-5
.const UI_TEXT_ROW       = 3        // scroll text window rows 3-20
.const UI_TEXT_ROWS      = 18
.const UI_TEXT_CELLS     = UI_TEXT_ROWS * SCREEN_COLS            // 720
.const UI_FNAME_ROW      = 10
.const UI_FNAME_COL      = 6
.const UI_FLASH_JIFFIES  = 5
.errorif UI_LIST_ROW + UI_LIST_ROWS > 20, "list must fit rows 4-19"
.errorif 1 + CAT_MAX_SIDS > UI_LIST_ROWS, "music list too long"
.errorif 2 + CAT_MAX_FONTS > UI_LIST_ROWS, "font list too long"
