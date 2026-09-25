#importonce
// ---------------------------------------------------------------------------
// fixture.asm - runtime test image (make fixture).
// Override the flags with: make fixture FIXTURE_FLAGS=<decimal>
// ---------------------------------------------------------------------------
.var fixtureFlags = cmdLineVars.containsKey("flags") ? cmdLineVars.get("flags").asNumber() : FLAG_ALL
.var fixtureMove  = cmdLineVars.containsKey("move") ? cmdLineVars.get("move").asNumber() : MOVE_STATIC
.var fixtureSpeed = cmdLineVars.containsKey("speed") ? cmdLineVars.get("speed").asNumber() : DEF_MOVE_SPEED
.var fixtureBig   = cmdLineVars.containsKey("big") ? cmdLineVars.get("big").asNumber() : 0
.var fixtureMc    = cmdLineVars.containsKey("mc") ? cmdLineVars.get("mc").asNumber() : 0

* = SID_START "fixture tune"
        .import binary "../build/testtune.prg", 2

* = CONFIG "fixture config"
        .text "IM"
        .byte CFG_VERSION_2
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
        .if (fixtureBig == 0) {
        .text "        C64 INTRO MAKER - FIXTURE       "
        .text "  ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789 "
        } else {
        .text "INTRO MAKER                             "
        .text "2X2 FONT!                               "
        }
        .byte fixtureBig != 0 ? 2 : 0, fixtureBig != 0 ? 2 : 0, fixtureMc
        .byte DEF_BIG_MC1, DEF_BIG_MC2, fixtureMove, fixtureSpeed, 0
        .word 0, 0, 0                   // no linked program
        .fill CFG_BIG_MAP - CFG_LINK_START - 2, 0
.errorif * != cfg_big_map, "fixture config layout (map)"
        // synthetic 2x2 font: tiles are boxes with the glyph number inside
        .fill BIG_GLYPHS, bigFixtureMap(i)

* = BIG_TILES "fixture big font"
        .for (var g = 0; g < BIG_GLYPH_COUNT_2X2; g++) {
            .for (var t = 0; t < 4; t++) {
                .for (var r = 0; r < 8; r++) {
                    .var edge = (r == 0 && t < 2) || (r == 7 && t > 1)
                    .var side = (t & 1) == 0 ? $80 : $01
                    .byte edge ? $ff : side | ((BIG_GLYPH_ORDER.get(g) * (r + 1) * 7) & $3c)
                }
            }
        }

.function bigFixtureMap(sc) {
    .for (var g = 0; g < BIG_GLYPH_COUNT_2X2; g++) {
        .if (BIG_GLYPH_ORDER.get(g) == sc) .return BIG_TILE_FIRST + g * 4
    }
    .return 0
}

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
