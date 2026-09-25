#importonce
// ---------------------------------------------------------------------------
// scroller.asm - 1x1 scroller in screen row 13 (38 column mode).
// Text bytes: $00-$3f screen code, $f1/$f2/$f4 speed, $f8 pause, $ff end.
// ---------------------------------------------------------------------------

scroll_init:
        lda #<TEXT
        sta rt_sptr
        lda #>TEXT
        sta rt_sptr + 1
        lda #XSCROLL_START
        sta rt_xscroll
        lda cfg_speed
        sta rt_speed
        lda #0
        sta rt_pause
        rts

// called once per frame from IRQ BOTTOM (~450 cycles on a shift frame)
scroll_update:
        lda rt_pause
        beq !+
        dec rt_pause
        rts
!:      lda rt_xscroll
        sec
        sbc rt_speed
        bmi !+
        sta rt_xscroll
        rts
!:      clc
        adc #8
        sta rt_xscroll
        ldx #0
!:      lda SCROLL_SCREEN + 1,x
        sta SCROLL_SCREEN,x
        inx
        cpx #SCREEN_COLS - 1
        bne !-
        jsr scroll_fetch
        sta SCROLL_SCREEN + SCREEN_COLS - 1
        rts

// next printable char -> A; control codes are executed immediately.
// A text without printable chars yields a space (no endless loop).
scroll_fetch:
        lda #0
        sta rt_wrapped
sf_next:
        ldy #0
        lda (rt_sptr),y
        cmp #TEXT_END_MARK
        bne !+
        lda rt_wrapped
        bne sf_space
        inc rt_wrapped
        lda #<TEXT
        sta rt_sptr
        lda #>TEXT
        sta rt_sptr + 1
        jmp sf_next
!:      inc rt_sptr
        bne !+
        inc rt_sptr + 1
!:      cmp #SC_MAX + 1
        bcc sf_done                 // printable
        cmp #CTRL_PAUSE
        bne !+
        lda #PAUSE_FRAMES
        sta rt_pause
        jmp sf_next
!:      cmp #CTRL_SPEED4 + 1       // $f1/$f2/$f4: speed in the low bits
        bcs sf_next                 // unknown code: skip
        and #CTRL_SPEED_MASK
        sta rt_speed
        jmp sf_next
sf_space:
        lda #SC_SPACE
sf_done:
        rts
