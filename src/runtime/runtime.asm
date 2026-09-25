#importonce
// ---------------------------------------------------------------------------
// runtime.asm - runtime_start: init, main loop, restore, exit.
// Reads only the config block, font, SID and scroll text.
// ---------------------------------------------------------------------------

rt_preview:     .byte 0             // 1 = return to the editor on SPACE

runtime_start:
        sei
        lda #CPU_IO_ONLY
        sta CPU_PORT
        lda #CIA_IRQ_ALL_OFF
        sta CIA1_ICR
        sta CIA2_ICR
        lda CIA1_ICR
        lda CIA2_ICR
        lda #0
        sta rt_exit_req
        sta rt_frame
        sta VIC_IRQ_ENABLE
        sta VIC_IDLE_BYTE           // saved intros may not contain $3fff
        lda #<irq_top
        sta HW_IRQ_VEC
        lda #>irq_top
        sta HW_IRQ_VEC + 1
        lda #<rt_nmi
        sta HW_NMI_VEC
        lda #>rt_nmi
        sta HW_NMI_VEC + 1
        lda #RT_D011                // bit 7 = 0: raster compare < 256
        sta VIC_CTRL1
        lda #RT_D016
        sta VIC_CTRL2
        lda #RT_D018
        sta VIC_MEMPTR
        lda #IRQ_TOP_LINE
        sta VIC_RASTER
        jsr rt_tables_init          // needs $01 = $35 (RAM under KERNAL)
        jsr rt_screen_init
        jsr spr_init
        jsr scroll_init
        jsr cyc_init
        jsr title_init
        lda #0
        sta rt_bar_phase
        sta SID_VOLUME
        lda cfg_flags
        and #FLAG_MUSIC
        beq !+
        lda cfg_init
        sta rt_init_call + 1
        lda cfg_init + 1
        sta rt_init_call + 2
        lda cfg_play
        sta rt_play_call + 1
        lda cfg_play + 1
        sta rt_play_call + 2
        lda cfg_subtune
rt_init_call:
        jsr DEF_INIT                // operand patched
!:      lda #VIC_IRQ_RASTER
        sta VIC_IRQ_ENABLE
        lda #VIC_IRQ_ACK_ALL
        sta VIC_IRQ_FLAG
        cli

// Main loop: per frame work (after IRQ BOTTOM). Instructions of at most 6
// cycles keep the entry jitter of the BARS double IRQ small.
rt_wait:
        lda rt_frame
        beq !+
        lda #0
        sta rt_frame
        jsr title_apply             // before line 48 of the next frame
        jsr cyc_update
!:      lda rt_exit_req
        beq rt_wait

        lda rt_preview
        bne rt_leave_preview
        // saved intro: reset the machine
        sei
        lda #0
        sta VIC_IRQ_ENABLE
        sta VIC_SPR_ENABLE
        sta SID_VOLUME
        lda #CPU_DEFAULT
        sta CPU_PORT
        jmp KERNAL_RESET

rt_leave_preview:
!:      lda #KEY_ROW_SPACE          // wait until SPACE is released
        sta CIA1_PRA
        lda CIA1_PRB
        and #KEY_BIT_SPACE
        beq !-
        sei
        lda #0
        sta VIC_IRQ_ENABLE
        lda #VIC_IRQ_ACK_ALL
        sta VIC_IRQ_FLAG
        lda #CIA_IRQ_TIMER_A
        sta CIA1_ICR
        lda #0
        sta SID_VOLUME
        sta VIC_SPR_ENABLE
        lda #RT_D016
        sta VIC_CTRL2
        lda #RT_D011
        sta VIC_CTRL1
        lda #CPU_DEFAULT
        sta CPU_PORT
        lda #0
        sta KERNAL_NDX              // drop the SPACE from the key buffer
        rts

rt_nmi:
        rti

// clear screen, set colours (the title is drawn by title_init)
rt_screen_init:
        lda cfg_border
        sta VIC_BORDER
        lda cfg_bg
        sta VIC_BG
        lda #SC_SPACE
        ldx #0
!:      sta SCREEN,x
        sta SCREEN + $100,x
        sta SCREEN + $200,x
        sta SCREEN + SCREEN_SIZE - $100,x
        inx
        bne !-
        lda cfg_scrollcol
        ldx #SCREEN_COLS - 1
!:      sta SCROLL_COLOR,x
        dex
        bpl !-
        rts
