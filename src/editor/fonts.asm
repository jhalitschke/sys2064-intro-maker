#importonce
// ---------------------------------------------------------------------------
// fonts.asm - built-in fonts: ROM copy and bold ROM.
// ---------------------------------------------------------------------------

// copy chars $00-$3f of the upper case ROM font to FONT
font_copy_rom:
        sei
        lda #CPU_CHARROM
        sta CPU_PORT
        ldx #0
!:      lda CHAR_ROM,x
        sta FONT,x
        lda CHAR_ROM + $100,x
        sta FONT + $100,x
        inx
        bne !-
        lda #CPU_DEFAULT
        sta CPU_PORT
        cli
        rts

// ROM font, every byte b | (b >> 1)
font_bold_rom:
        jsr font_copy_rom
        ldx #0
!:      lda FONT,x
        lsr
        ora FONT,x
        sta FONT,x
        lda FONT + $100,x
        lsr
        ora FONT + $100,x
        sta FONT + $100,x
        inx
        bne !-
        rts
