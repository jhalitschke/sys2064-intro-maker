#importonce
// ---------------------------------------------------------------------------
// sprites.asm - 8 hires balls on a sine path (sprite zone, lines 76-125).
// ---------------------------------------------------------------------------

spr_init:
        lda #0
        sta VIC_SPR_ENABLE
        sta VIC_SPR_YEXP
        sta VIC_SPR_XEXP
        sta VIC_SPR_MC
        sta VIC_SPR_PRIO
        sta rt_spr_px
        sta rt_spr_py
        ldx #SPR_COUNT - 1
!:      lda #SPRITE_PTR
        sta SPRITE_PTRS,x
        lda rt_spr_colors,x
        sta VIC_SPR0_COL,x
        dex
        bpl !-
        lda cfg_flags
        and #FLAG_SPRITES
        beq !+
        jsr spr_update              // positions before the first frame
        lda #(1 << SPR_COUNT) - 1
        sta VIC_SPR_ENABLE
!:      rts

// called in IRQ TOP; ~8 x 40 = 320 cycles
spr_update:
        lda cfg_flags
        and #FLAG_SPRITES
        beq su_done
        lda rt_spr_px
        sta rt_t0
        lda rt_spr_py
        sta rt_t1
        lda #0
        sta rt_msb
        ldx #0                      // 2 * sprite index
su_loop:
        ldy rt_t0
        lda spr_x2,y
        asl                         // x = 2 * table, bit 8 -> carry
        sta VIC_SPR0_X,x
        ror rt_msb                  // sprite 0 ends up in bit 0
        ldy rt_t1
        lda spr_y,y
        sta VIC_SPR0_Y,x
        lda rt_t0
        clc
        adc #SPR_PHASE_STEP
        and #SIN_LEN - 1
        sta rt_t0
        lda rt_t1
        clc
        adc #SPR_PHASE_STEP
        and #SIN_LEN - 1
        sta rt_t1
        inx
        inx
        cpx #SPR_COUNT * 2
        bne su_loop
        lda rt_msb
        sta VIC_SPR_XMSB
        lda rt_spr_px
        clc
        adc #SPR_X_SPEED
        and #SIN_LEN - 1
        sta rt_spr_px
        lda rt_spr_py
        clc
        adc #SPR_Y_SPEED
        and #SIN_LEN - 1
        sta rt_spr_py
su_done:
        rts
