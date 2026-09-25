#importonce
// ---------------------------------------------------------------------------
// demo.asm - demo intro for the web page (make demo): all effects, the
// ROM 2X2 title font (drawn at start from the machine's own character ROM,
// so the file holds no ROM data) on a figure eight, the test tune and a
// typical intro text. The crew and the greeted groups are made up.
// ---------------------------------------------------------------------------

.function line40(s) {
    .var r = s
    .for (var i = s.size(); i < TITLE_LINE_LEN; i++) .eval r = r + " "
    .return r
}

* = SID_START "demo tune"
        .import binary "../build/testtune.prg", 2

* = CONFIG "demo config"
        .text "IM"
        .byte CFG_VERSION_2
        .byte FLAG_ALL
        .byte 0                     // border
        .byte 0                     // background
        .byte 7                     // scroller
        .byte 1                     // title (colour cycle is on)
        .byte 7                     // bar preset: rainbow
        .byte 2                     // scroll speed
        .word DEF_INIT
        .word DEF_PLAY
        .byte DEF_SUBTUNE
        .byte 0
.errorif * != cfg_title, "demo config layout"
        .encoding "screencode_upper"
        .text line40("PIXEL ZEPHYR")
        .text line40("PRESENTS")
        .byte 0, 0, 0               // big font: set by font_rom2x2 at start
        .byte DEF_BIG_MC1, DEF_BIG_MC2, MOVE_EIGHT, 2, 0
        .word 0, 0, 0, 0            // no linked program
        .fill CFG_BIG_MAP - CFG_LINK_SRC - 2, 0
.errorif * != cfg_big_map, "demo config layout (map)"
        .fill BIG_GLYPHS, 0

* = TEXT "demo text"
        .encoding "screencode_upper"
        .text "      YO! PIXEL ZEPHYR IS BACK WITH ANOTHER FRESH RELEASE FOR YOUR BREADBOX...   "
        .byte CTRL_SPEED4
        .text "FASTER THAN A 1541 WITH A FASTLOADER!   "
        .byte CTRL_SPEED1
        .text "...AND NOW NICE AND SLOW FOR THE GREETINGS...   "
        .byte CTRL_SPEED2
        .text "HOT GREETINGS FLY OUT TO: QUARTZ QUOKKAS - TAPE TAPIRS - NIBBLE NOMADS - "
        .text "DOTMATRIX DINGOS - CYAN CORMORANTS - RASTER RACCOONS - AND EVERYONE WE FORGOT!   "
        .text "--- 6502 FOREVER ---"
        .byte CTRL_PAUSE
        .text "   INTRO MADE WITH THE C64 INTRO MAKER. PRESS SPACE TO RESTART THE MACHINE...      "
        .byte TEXT_END_MARK
.errorif * - TEXT > TEXT_MAX + 1, "demo text too long"

* = EDITOR_CODE "demo entry"
fixture_start:
        jsr font_copy_rom
        jsr font_rom2x2
        jmp runtime_start
#import "editor/fonts.asm"
#import "editor/rom2x2.asm"
#import "editor/vars.asm"
