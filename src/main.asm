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
        jmp editor_start            // operand patched to runtime_start on save
.errorif * != RT_CODE, "entry JMP must end at RT_CODE"

// M0 placeholder editor
* = EDITOR_CODE "editor"
editor_start:
        inc VIC_BORDER
        jmp editor_start
.errorif * > EDITOR_END, "editor code overflow"
