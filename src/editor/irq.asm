#importonce
// ---------------------------------------------------------------------------
// irq.asm (editor) - one raster IRQ per frame via $0314: music + KERNAL
// keyboard scan. CIA1 IRQs stay off, so the music plays at 50 Hz.
// ---------------------------------------------------------------------------

ed_irq_install:
        sei
        lda #CIA_IRQ_ALL_OFF
        sta CIA1_ICR
        lda CIA1_ICR
        lda #<ed_irq
        sta KERNAL_IRQ_VEC
        lda #>ed_irq
        sta KERNAL_IRQ_VEC + 1
        lda #ED_IRQ_LINE
        sta VIC_RASTER
        lda #ED_D011                // bit 7 = 0: raster compare < 256
        sta VIC_CTRL1
        lda #VIC_IRQ_RASTER
        sta VIC_IRQ_ENABLE
        lda #VIC_IRQ_ACK_ALL
        sta VIC_IRQ_FLAG
        cli
        rts

ed_irq:
        lda #VIC_IRQ_RASTER
        sta VIC_IRQ_FLAG
        lda ed_music_on
        beq !+
        jsr ed_call_play
!:      jmp KERNAL_IRQ_EXIT

ed_call_play:
        jmp (cfg_play)

ed_call_init:
        jmp (cfg_init)

// stop the music before loading into the SID area
ed_music_stop:
        lda #0
        sta ed_music_on
        sta SID_VOLUME
        rts

// (re)start the tune from the config if the MUSIC flag is set
ed_music_start:
        jsr ed_music_stop
        lda cfg_flags
        and #FLAG_MUSIC
        beq !+
        lda cfg_subtune
        jsr ed_call_init
        lda #1
        sta ed_music_on
!:      rts
