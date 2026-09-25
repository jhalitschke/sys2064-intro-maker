// ---------------------------------------------------------------------------
// main.asm - BASIC stub, entry JMP and all imports.
// Build with -define FIXTURE for the runtime test image.
// ---------------------------------------------------------------------------
#import "shared/memmap.asm"
#import "shared/config.asm"

* = BASIC_START "basic stub"
        .word stub_end              // next line
        .word 10                    // line number
        .byte $9e                   // SYS token
        .text toIntString(BASIC_SYS_ADDR)
        .byte 0
stub_end:
        .word 0
.errorif * > ENTRY_JMP, "BASIC stub too long"

* = ENTRY_JMP "entry jmp"
#if FIXTURE
        jmp fixture_start
#else
        jmp editor_start            // operand patched to runtime_start on save
#endif
.errorif * != RT_CODE, "entry JMP must end at RT_CODE"

// ---- Runtime ----------------------------------------------------------------
* = RT_CODE "runtime"
#import "runtime/irq.asm"               // first: timing code within one page
#import "runtime/runtime.asm"
#import "runtime/scroller.asm"
#import "runtime/bars.asm"
#import "runtime/sprites.asm"
#import "runtime/colorcycle.asm"
#import "runtime/tables.asm"
.errorif * > RT_CODE_END, "runtime code overflow"

* = SPRITE_DATA "sprite ball"
        SpriteBall()
.errorif * > SPRITE_DATA + 64, "sprite data overflow"

* = RT_TABLES
        RuntimeTables()
.errorif * > RT_TABLES_END, "runtime tables overflow"

#if FIXTURE
// ---- Fixture: runtime test image ------------------------------------------
#import "fixture.asm"
#else
// ---- Editor -----------------------------------------------------------------
* = TEXT "scroll text"
        .byte TEXT_END_MARK

* = EDITOR_CODE "editor"
#import "editor/editor.asm"
#import "editor/irq.asm"
#import "editor/ui.asm"
#import "editor/lists.asm"
#import "editor/textedit.asm"
#import "editor/disk.asm"
#import "editor/fonts.asm"
.errorif * > EDITOR_END, "editor code overflow"
#import "editor/vars.asm"
#endif
