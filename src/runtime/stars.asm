#importonce
// ---------------------------------------------------------------------------
// stars.asm - star sprite frames, drawn at runtime start (not saved):
// arms (i, 0) and diagonals (i, i), each plotted in the 4 rotations.
// ---------------------------------------------------------------------------

stars_init:
        lda #0
        ldx #STAR_TAPE_BLOCKS * 64  // > 128 bytes: count down to 1
!:      sta STAR_TAPE - 1,x
        dex
        bne !-
        ldx #64
!:      sta SPRITE_DATA - 1,x
        dex
        bne !-
        ldx #STAR_FRAMES - 1
si_frame:
        stx rt_mv_tmp
        lda star_frame_lo,x
        sta rt_ptr
        lda star_frame_hi,x
        sta rt_ptr + 1
        lda star_arm,x              // arms: i = arm .. 0
        sta rt_t2
!:      lda rt_t2
        ldy #0
        jsr star_plot4
        dec rt_t2
        bpl !-
        ldx rt_mv_tmp               // diagonals: i = arm / 2 .. 1
        lda star_arm,x
        lsr
        beq si_next
        sta rt_t2
!:      lda rt_t2
        tay
        jsr star_plot4
        dec rt_t2
        bne !-
si_next:
        ldx rt_mv_tmp
        dex
        bpl si_frame
        rts

star_frame_lo:  .byte <STAR_TAPE, <(STAR_TAPE + 64), <(STAR_TAPE + 128), <SPRITE_DATA
star_frame_hi:  .byte >STAR_TAPE, >(STAR_TAPE + 64), >(STAR_TAPE + 128), >SPRITE_DATA
star_arm:       .byte 1, 3, 6, 10                   // small -> big
.errorif * - star_arm != STAR_FRAMES, "star table size"
.errorif STAR_CENTER + 10 > 20, "star leaves the sprite"
