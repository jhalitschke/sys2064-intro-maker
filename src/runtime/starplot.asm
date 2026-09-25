#importonce
// starplot.asm - A = dx, Y = dy: set the pixels (C + dx, C + dy) of the
// star frame at rt_ptr in all 4 rotations (dx, dy) -> (-dy, dx).
star_plot4:
        sta rt_t0
        sty rt_t1
        lda #4
        sta rt_msb
sp_loop:
        lda rt_t1                   // row offset: y * 3
        clc
        adc #STAR_CENTER
        sta rt_t3
        asl
        adc rt_t3
        sta rt_t3
        lda rt_t0
        clc
        adc #STAR_CENTER
        pha
        lsr
        lsr
        lsr
        clc
        adc rt_t3
        tay
        pla
        and #7
        tax
        lda star_bits,x
        ora (rt_ptr),y
        sta (rt_ptr),y
        lda rt_t1                   // rotate by 90 degrees
        eor #$ff
        clc
        adc #1
        tax
        lda rt_t0
        sta rt_t1
        stx rt_t0
        dec rt_msb
        bne sp_loop
        rts
star_bits:      .byte $80, $40, $20, $10, $08, $04, $02, $01
