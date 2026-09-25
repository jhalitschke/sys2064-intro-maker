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
.const SC_DIGIT_0        = $30
.const SC_CTRL_SPEED1    = $31 | SC_REVERSE     // shown as reverse 1/2/4/P
.const SC_CTRL_SPEED2    = $32 | SC_REVERSE
.const SC_CTRL_SPEED4    = $34 | SC_REVERSE
.const SC_CTRL_PAUSE     = $10 | SC_REVERSE
.const SC_UNKNOWN        = $3f | SC_REVERSE
.const STR_END           = $ff      // editor string terminator
.const UI_POW10_COUNT    = 4        // up to 4 decimal digits

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
.const CAT_MAX_FONTS     = 15
.const FNAME_MAX         = 16
.const DIR_MAX           = 144      // 1541 directory entries
.const DIR_NAME_LEN      = 16
.const CATALOG_FNAME_LEN = 7        // "CATALOG"

// ---- KERNAL file numbers ------------------------------------------------------
.const LFN_DATA          = 1
.const SA_LOAD_FILE_ADDR = 1        // LOAD to the address in the file
.const SA_SAVE           = 0
.const LFN_CMD           = 15       // command / error channel
.const SA_CMD            = 15
.const LFN_FILE          = 2
.const SA_READ           = 0        // load channel: "$" gives the listing
.const ST_EOF            = $40      // READST bits
.const ST_ERRORS         = $83      // timeouts, device not present

// ---- PSID header (big endian) ------------------------------------------------
.const PSID_DATA         = $06
.const PSID_LOAD         = $08
.const PSID_INIT         = $0a
.const PSID_PLAY         = $0c
.const PSID_START        = $10
.const PSID_SPEED        = $12      // 32 bit
.const PSID_NAME         = $16      // 32 bytes ASCII
.const PSID_SPEED_BITS   = 32

// ---- character codes -----------------------------------------------------------
.const PET_QUOTE         = $22
.const PET_P             = $50
.const PET_R             = $52
.const PET_G             = $47
.const ASCII_LOWER_A     = $61
.const ASCII_LOWER_Z     = $7a
.const ASCII_UPPER_Z     = $5a

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
.const UI_TEXTLEN_COL    = 13       // "(n/5118)" behind "6 SCROLLTEXT"
.const UI_BLOCK_COL      = 16       // colour blocks / effect values
.const SC_PAREN_OPEN     = $28
.const MIN_DRIVE         = 8
.const ED_MENU_ITEMS     = 8        // main menu keys 1-8
.const ED_COLOR_ITEMS    = 4        // border, background, scroller, title
.const ED_EFFECT_ITEMS   = 6
.const ED_EFFECT_PRESET  = 2        // effect entry index of the bar preset
.const LIST_MUSIC        = 0
.const LIST_FONT         = 1
.const LIST_FILES        = 2
.const FONT_BUILTIN_BOLD = 1        // font list: 0 ROM, 1 ROM BOLD, catalog
.const FONT_BUILTINS     = 2
.const ES_KEY_COUNT      = 11       // scroll text editor command keys
.const ES_CODE_COUNT     = 4        // control codes
.const MAX_SPEED         = 4
.errorif UI_LIST_ROW + UI_LIST_ROWS > 20, "list must fit rows 4-19"

// ---- Stable raster timing (BARS IRQ, see runtime/irq.asm) ------------------
.const BARS_DELAY        = 8        // stage 2 wait loop before the $d012 compare
.const BARS_ALIGN        = 10       // 5 * n + 1 cycles: colour writes land in the h-blank
.const BARS_NOPS         = 0        // extra 2-cycle NOPs before the bar loop
.const BARS_PAD_LOOPS    = 5        // bar loop padding: 5 * n - 1 cycles
