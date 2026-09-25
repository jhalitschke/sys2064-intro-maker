#importonce
// ---------------------------------------------------------------------------
// irq.asm - raster IRQ chain (KERNAL off, vector at $fffe).
//   TOP    $10  VIC setup, sprites, title colours, bar buffers
//   BARS   $80  double IRQ -> stable raster, 80 lines FLD + bars
//   SCROLL $e8  38 columns + xscroll
//   BOTTOM $f8  40 columns, music, scroller, SPACE check
// ---------------------------------------------------------------------------

.macro IrqEnter() {
        pha
        txa
        pha
        tya
        pha
}

.macro IrqNext(handler, line) {
        lda #<handler
        sta HW_IRQ_VEC
        lda #>handler
        sta HW_IRQ_VEC + 1
        lda #line
        sta VIC_RASTER
}

// ---- BARS: double IRQ ------------------------------------------------------
// Budget: lines 128-211 completely (2 lines stabilising, 80 lines loop).
// Stage 1 at line $80 (128). Entry jitter: 7 IRQ cycles + 0..3 cycles of
// the interrupted main loop instruction.
irq_bars:
        sta rt_bars_a + 1           // 4   self-mod save (SID play may use ZP)
        stx rt_bars_x + 1           // 4
        sty rt_bars_y + 1           // 4
        lda #FLD_PRE_D011           // 2   YSCROLL 4: no badline in 128-131
        sta VIC_CTRL1               // 4
        lda #<irq_bars_stable       // 2
        sta HW_IRQ_VEC              // 4
        lda #>irq_bars_stable       // 2
        sta HW_IRQ_VEC + 1          // 4
        inc VIC_RASTER              // 6   stage 2 at line 129
        lda #VIC_IRQ_RASTER         // 2
        sta VIC_IRQ_FLAG            // 4
        tsx                         // 2
        cli                         // 2 = 46 + entry (~10) -> cycle ~56
        nop                         // stage 2 hits inside the NOPs:
        nop                         // jitter reduced to 0/1 cycle
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop

// Stage 2 at line 129 (non-badline, no sprites: 63 cycles per line).
irq_bars_stable:
        txs                         // 2   drop stage 2 IRQ frame
        ldx #BARS_DELAY             // 2
!:      dex                         // 2
        bne !-                      // 3 / 2
        bit $00                     // 3
        lda VIC_RASTER              // 4
        cmp VIC_RASTER              // 4   reads on the line change?
        beq !+                      // 3 (same line) / 2 (changed)
!:                                  // now at a fixed cycle of line 130
        ldx #BARS_ALIGN             // 2
!:      dex                         // 2
        bne !-                      // 3 / 2 -> 5 * BARS_ALIGN - 1
        .for (var i = 0; i < BARS_NOPS; i++) {
            nop                     // 2 each
        }
        ldx #0                      // 2

// FLD + bars loop: exactly 63 cycles per iteration = one raster line.
// Tables must not cross a page (checked in memmap.asm).
bars_loop:
        lda border_buf,x            // 4    4
        ldy bg_buf,x                // 4    8
        sta VIC_BORDER              // 4   12   write on cycle 12
        sty VIC_BG                  // 4   16   write on cycle 16
        lda fld_tab,x               // 4   20
        sta VIC_CTRL1               // 4   24   YSCROLL for the next line
        ldy #BARS_PAD_LOOPS         // 2   26
!:      dey                         // 2
        bne !-                      // 3/2 50   (5 * 5 - 1 = 24)
        nop                         // 2   52
        nop                         // 2   54
        nop                         // 2   56
        inx                         // 2   58
        cpx #FLD_LINES              // 2   60
        bne bars_loop               // 3   63
        // line FLD_LAST_LINE + 1 is a badline (text row 10): restore
        // the configured colours before its display starts
        lda cfg_border              // 4
        ldy cfg_bg                  // 4
        sta VIC_BORDER              // 4
        sty VIC_BG                  // 4   before the badline DMA stalls the CPU
        IrqNext(irq_scroll, IRQ_SCROLL_LINE)
        lda #VIC_IRQ_RASTER         // ack stage 2
        sta VIC_IRQ_FLAG
rt_bars_a:
        lda #0                      // self-mod restore
rt_bars_x:
        ldx #0
rt_bars_y:
        ldy #0
        rti
irq_bars_end:
// branches in this block must not cross a page (+1 cycle)
.errorif (irq_bars >> 8) != ((irq_bars_end - 1) >> 8), "BARS IRQ crosses a page"


// ---- TOP -------------------------------------------------------------------
// Budget: sprites ~350, colour cycle ~960, bar buffers ~2300 cycles
// (+ sprite DMA from line 76). Measured in x64sc with all flags set:
// done by raster line 76, well before BARS at $80 (128).
irq_top:
        IrqEnter()
        lda #RT_D016
        sta VIC_CTRL2
        lda #RT_D018
        sta VIC_MEMPTR
        lda #RT_D011
        sta VIC_CTRL1
        jsr spr_update
        jsr cyc_update
        jsr bars_prepare
irq_top_done:                       // (label for timing measurements)
        IrqNext(irq_bars, IRQ_BARS_LINE)
        jmp irq_exit

// ---- SCROLL ----------------------------------------------------------------
// Budget: ~60 cycles (one raster line).
irq_scroll:
        IrqEnter()
        lda rt_xscroll
        ora #RT_D016_38
        sta VIC_CTRL2
        IrqNext(irq_bottom, IRQ_BOTTOM_LINE)
        jmp irq_exit

// ---- BOTTOM ----------------------------------------------------------------
// Budget: SID play (tune dependent) + scroller ~500 cycles. Measured with
// the test tune: done by raster line 261; 80 lines are available until TOP.
irq_bottom:
        IrqEnter()
        lda #RT_D016
        sta VIC_CTRL2
        lda cfg_flags
        and #FLAG_MUSIC
        beq !+
rt_play_call:
        jsr DEF_PLAY                // operand patched in runtime_start
!:      jsr scroll_update
irq_bottom_done:                    // (label for timing measurements)
        lda #KEY_ROW_SPACE
        sta CIA1_PRA
        lda CIA1_PRB
        and #KEY_BIT_SPACE
        bne !+
        lda #1
        sta rt_exit_req
!:      IrqNext(irq_top, IRQ_TOP_LINE)
        // fall through

irq_exit:
        lda #VIC_IRQ_RASTER
        sta VIC_IRQ_FLAG
        pla
        tay
        pla
        tax
        pla
        rti

