#importonce
// ---------------------------------------------------------------------------
// tables.asm - runtime tables: the saved sine (assembler) and the RAM tables
// under the KERNAL, built from it at start (rt_tables_init).
// ---------------------------------------------------------------------------

// Saved table: import with * = RT_TABLES
.macro RuntimeTables() {
    * = mv_sin "movement sine"
        .fill SIN_LEN, round(127 * sin(toRadians(i * 360 / SIN_LEN))) & $ff
}

// Small tables: emitted where this file is imported (runtime segment)
// 8 presets x 15 colours, symmetric gradients
// symmetric gradients: first 8 of 15 colours, mirrored by rt_tables_init
// into rt_presets (RAM)
rt_preset_halves:
        .byte 6, 6,14,14, 3, 3, 1, 1        // blue
        .byte 2, 2, 8, 8,10,10, 7, 1        // fire
        .byte 11,11,5, 5,13,13, 1, 1        // green
        .byte 11,11,12,12,15,15,1, 1        // grey
        .byte 6, 6, 4, 4,10,10, 1, 1        // purple
        .byte 9, 9, 8, 8, 7, 7, 1, 1        // gold
        .byte 6, 6, 3, 3,13,13, 1, 1        // cyan
        .byte 2, 8, 7, 5, 3,14, 6, 1        // rainbow
.errorif * - rt_preset_halves != PRESET_COUNT * PRESET_HALF, "preset table size"
rt_preset_offs:
        .fill PRESET_COUNT, i * BAR_HEIGHT
rt_bar_phase_offs:
        .fill BAR_COUNT, i * BAR_PHASE_STEP
rt_bar_fixed:
        .byte BAR_FIXED_0, BAR_FIXED_1, BAR_FIXED_2
rt_cyc_tab:
        .byte 9, 2, 8,10,15, 7, 1, 1, 1, 7,15,10, 8, 2, 9, 9
rt_spr_colors:
        .byte 1, 7, 3, 5,13,14,10,15

// 21x21 ball, generated
.macro SpriteBall() {
    .for (var y = 0; y < 21; y++) {
        .for (var b = 0; b < 3; b++) {
            .var v = 0
            .for (var bit = 0; bit < 8; bit++) {
                .var x = b * 8 + bit
                .var dx = x - 10
                .var dy = y - 10
                .if (x < 21 && dx * dx + dy * dy <= 110) .eval v = v | ($80 >> bit)
            }
            .byte v
        }
    }
    .byte 0
}
