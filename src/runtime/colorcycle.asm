#importonce
// ---------------------------------------------------------------------------
// colorcycle.asm - title colour cycle in the colour RAM of the title rows.
// ---------------------------------------------------------------------------

cyc_init:
        lda #0
        sta rt_cyc_phase
        sta rt_cyc_div
        rts

// called by the main loop; every CYC_DIVIDER frames
// rows x title columns x 16 cycles (~1400 for a 4 row, 22 column title)
cyc_update:
        lda cfg_flags
        and #FLAG_TITLE_CYCLE
        beq cu_done
        inc rt_cyc_div
        lda rt_cyc_div
        cmp #CYC_DIVIDER
        bcc cu_done
        lda #0
        sta rt_cyc_div
        inc rt_cyc_phase
        // colour(column) = rt_cyc_ext[column + phase & 15]
        lda rt_cyc_phase
        and #CYC_LEN - 1
        clc
        adc #<rt_cyc_ext
        sta rt_ptr2
        lda #>rt_cyc_ext
        adc #0
        sta rt_ptr2 + 1
        lda rt_rows
        sta rt_t0
        lda rt_wchars               // empty title
        beq cu_done
        ldx rt_cur_row
        bmi cu_done
!:      lda tr_row_lo,x
        sta rt_ptr
        lda tr_row_hi,x
        clc
        adc #(>COLRAM) - (>SCREEN)
        sta rt_ptr + 1
        lda rt_cur_col
        clc
        adc rt_wchars
        tay                         // behind the title's last column
!:      dey                         // 2
        lda (rt_ptr2),y             // 5
        sta (rt_ptr),y              // 6
        cpy rt_cur_col              // 3
        bne !-                      // 3 = 19 per byte
        inx
        dec rt_t0
        bne !--
cu_done:
        rts
