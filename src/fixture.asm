#importonce
// ---------------------------------------------------------------------------
// fixture.asm - runtime test image (make fixture).
// Override the flags with: make fixture FIXTURE_FLAGS=<decimal>
// ---------------------------------------------------------------------------
.var fixtureFlags = cmdLineVars.containsKey("flags") ? cmdLineVars.get("flags").asNumber() : FLAG_ALL

* = SID_START "fixture tune"
        .import binary "../build/testtune.prg", 2

* = CONFIG "fixture config"
        .text "IM"
        .byte CFG_VERSION_1
        .byte fixtureFlags
        .byte 6                     // border
        .byte 0                     // background
        .byte 1                     // scroller
        .byte 7                     // title
        .byte 1                     // bar preset
        .byte 2                     // speed
        .word DEF_INIT
        .word DEF_PLAY
        .byte DEF_SUBTUNE
        .byte 0
.errorif * != cfg_title, "fixture config layout"
        .encoding "screencode_upper"
        .text "        C64 INTRO MAKER - FIXTURE       "
        .text "  ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789 "

* = TEXT "fixture text"
        .text "HELLO! THIS IS THE FIXTURE SCROLL TEXT...   "
        .byte CTRL_SPEED1
        .text "SLOW AT SPEED 1   "
        .byte CTRL_SPEED4
        .text "FAST AT SPEED 4   "
        .byte CTRL_SPEED2
        .text "NORMAL AT SPEED 2   "
        .byte CTRL_PAUSE
        .text "AFTER THE PAUSE IT GOES ON... 0123456789 !?.,-:/()   "
        .byte TEXT_END_MARK

* = EDITOR_CODE "fixture entry"
fixture_start:
        jsr font_copy_rom
        jmp runtime_start
#import "editor/fonts.asm"
