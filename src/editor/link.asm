#importonce
// ---------------------------------------------------------------------------
// link.asm - link the intro in front of a program from disk.
// Saved file: intro $0801-$3fff, mover (LINK_MOVER), program data
// (LINK_SRC). SPACE in the intro: runtime copies the mover to the tape
// buffer, the mover moves the data to its load address and starts it with
// RUN (BASIC) or SYS.
// ---------------------------------------------------------------------------

ed_link:
        jsr ed_draw_link
!:      jsr ui_getkey
        cmp #KEY_STOP
        bne !+
        rts
!:      sec
        sbc #KEY_1
        cmp #ED_LINK_ITEMS
        bcs !--
        tax
        bne !+
        jsr ed_link_select          // 1: program from disk
        jmp ed_link
!:      lda cfg_link_len            // 2-4 need a program
        ora cfg_link_len + 1
        beq ed_link
        dex
        bne !+
        lda cfg_link_start          // 2: RUN <-> SYS load address
        ora cfg_link_start + 1
        beq lk_sys
        lda #0
        sta cfg_link_start
        sta cfg_link_start + 1
        jmp ed_link
lk_sys:
        lda cfg_link_dest
        sta cfg_link_start
        lda cfg_link_dest + 1
        sta cfg_link_start + 1
        jmp ed_link
!:      dex
        bne !+
        jsr ed_hex_input            // 3: SYS address
        bcs ed_link
        stx cfg_link_start
        sty cfg_link_start + 1
        jmp ed_link
!:      lda #0                      // 4: remove
        sta cfg_link_len
        sta cfg_link_len + 1
        jmp ed_link

ed_draw_link:
        jsr ui_clear
        Print(0, UI_HEAD_ROW, UI_COL_HEAD, str_link)
        Print(0, UI_MENU_ROW + 0, UI_COL_TEXT, str_l_prog)
        Print(0, UI_MENU_ROW + 1, UI_COL_TEXT, str_l_start)
        Print(0, UI_MENU_ROW + 2, UI_COL_TEXT, str_l_sys)
        Print(0, UI_MENU_ROW + 3, UI_COL_TEXT, str_l_remove)
        lda #<str_hint_link
        ldy #>str_hint_link
        jsr ui_hint
        Goto(UI_BLOCK_COL, UI_MENU_ROW + 0, UI_COL_KEY)
        jsr ed_put_link_name
        lda cfg_link_len
        ora cfg_link_len + 1
        beq lk_drawn
        Goto(UI_BLOCK_COL, UI_MENU_ROW + 1, UI_COL_KEY)
        lda cfg_link_start
        ora cfg_link_start + 1
        bne !+
        lda #<str_l_run
        ldy #>str_l_run
        jsr ui_puts
        jmp lk_range
!:      lda #<str_l_sys_at
        ldy #>str_l_sys_at
        jsr ui_puts
        lda cfg_link_start + 1
        ldx cfg_link_start
        jsr ui_puthex16
lk_range:
        Print(0, UI_MENU_ROW + 5, UI_COL_TEXT, str_l_load)
        lda cfg_link_dest + 1
        ldx cfg_link_dest
        jsr ui_puthex16
        lda #SC_MINUS
        jsr ui_putc
        lda cfg_link_dest           // last byte: dest + len - 1
        clc
        adc cfg_link_len
        tax
        lda cfg_link_dest + 1
        adc cfg_link_len + 1
        cpx #0
        bne !+
        sec
        sbc #1
!:      dex
        jsr ui_puthex16
lk_drawn:
        rts

// main menu value of "8 LINK PROGRAM"
ed_draw_link_value:
        Goto(UI_VALUE_COL + 6, UI_MENU_ROW + 7, UI_COL_KEY)
        lda cfg_link_len
        ora cfg_link_len + 1
        bne ed_put_link_name
        rts

// name of the linked program or NONE at the cursor
ed_put_link_name:
        lda cfg_link_len
        ora cfg_link_len + 1
        bne !+
        lda #<str_l_none
        ldy #>str_l_none
        jmp ui_puts
!:      ldx #0
!:      cpx ed_link_name_len
        beq !+
        lda ed_link_name,x
        jsr ui_pet2sc
        stx ed_t0
        jsr ui_putc
        ldx ed_t0
        inx
        bne !-
!:      rts

ls_error:
        jsr dr_close
        lda #<str_load_error
        ldy #>str_load_error
        jsr ed_status_set
        jmp disk_read_status

// pick a PRG, get its load address and length (VERIFY reads the whole
// file without writing memory)
ed_link_select:
        jsr ed_pick_file
        bcc !+
        rts
!:
        lda ed_file_len             // load address: first two bytes
        ldx #<ed_file_name_buf
        ldy #>ed_file_name_buf
        jsr SETNAM
        lda #LFN_FILE
        ldx ed_dev
        ldy #SA_READ
        jsr SETLFS
        jsr OPEN
        bcs ls_error
        ldx #LFN_FILE
        jsr CHKIN
        bcs ls_error
        jsr CHRIN
        sta ed_load
        jsr CHRIN
        sta ed_load + 1
        jsr READST
        and #ST_ERRORS
        bne ls_error
        jsr dr_close
        lda #<str_l_verify
        ldy #>str_l_verify
        jsr ui_status
        lda ed_file_len
        ldx #<ed_file_name_buf
        ldy #>ed_file_name_buf
        jsr SETNAM
        lda #LFN_DATA
        ldx ed_dev
        ldy #SA_LOAD_FILE_ADDR
        jsr SETLFS
        lda #1                      // verify
        jsr LOAD
        bcs ls_error
        // length = end - load; load >= LINK_DEST_MIN, end <= LINK_END_MAX,
        // LINK_SRC + length <= LINK_END_MAX
        txa
        sec
        sbc ed_load
        sta ed_t0
        tya
        sbc ed_load + 1
        sta ed_t1
        ora ed_t0
        beq ls_bad
        lda ed_load + 1
        cmp #>LINK_DEST_MIN
        bcc ls_bad
        cpx #<(LINK_END_MAX + 1)
        tya
        sbc #>(LINK_END_MAX + 1)
        bcs ls_bad
        lda ed_t0
        cmp #<(LINK_END_MAX - LINK_SRC + 1)
        lda ed_t1
        sbc #>(LINK_END_MAX - LINK_SRC + 1)
        bcs ls_bad
        lda ed_t0
        sta cfg_link_len
        lda ed_t1
        sta cfg_link_len + 1
        ldx ed_load
        ldy ed_load + 1
        stx cfg_link_dest
        sty cfg_link_dest + 1
        cpx #<BASIC_START           // BASIC program: RUN, else SYS load
        bne !+
        cpy #>BASIC_START
        bne !+
        ldx #0
        ldy #0
!:      stx cfg_link_start
        sty cfg_link_start + 1
        lda #<LINK_SRC
        sta cfg_link_src
        lda #>LINK_SRC
        sta cfg_link_src + 1
        ldx ed_file_len
        stx ed_link_name_len
        dex
!:      lda ed_file_name_buf,x
        sta ed_link_name,x
        dex
        bpl !-
        jmp ed_status_clear
ls_bad:
        lda #<str_l_bad
        ldy #>str_l_bad
        jmp ed_status_set

// 4 hex digits -> X/Y (lo/hi), carry set on RUN/STOP
ed_hex_input:
        lda #0
        sta ed_t2                   // digits
hi_draw:
        Goto(UI_BLOCK_COL, UI_MENU_ROW + 2, UI_COL_KEY)
        lda #SC_DOLLAR
        jsr ui_putc
        ldx #0
!:      cpx ed_t2
        beq !+
        lda ed_hex_buf,x
        stx ed_t0
        jsr ui_putc
        ldx ed_t0
        inx
        bne !-
!:      lda #SC_REV_SPACE
        jsr ui_putc
        lda #SC_SPACE
        jsr ui_putc
hi_key:
        jsr ui_getkey
        cmp #KEY_STOP
        bne !+
        sec
        rts
!:      cmp #KEY_DEL
        bne !+
        lda ed_t2
        beq hi_key
        dec ed_t2
        jmp hi_draw
!:      cmp #KEY_RETURN
        beq hi_done
        ldx ed_t2
        cpx #4
        beq hi_key
        jsr ui_pet2sc               // 0-9 -> $30-$39, A-F -> 1-6
        bcs hi_key
        cmp #SC_DIGIT_0 + 10
        bcs hi_key
        cmp #SC_DIGIT_0
        bcs !+
        cmp #1
        bcc hi_key
        cmp #7
        bcs hi_key
!:      sta ed_hex_buf,x
        inc ed_t2
        jmp hi_draw
hi_done:
        lda ed_t2
        cmp #4
        bne hi_key
        ldx #0                      // digits -> nibbles
!:      lda ed_hex_buf,x
        cmp #SC_DIGIT_0
        bcs !+
        adc #9                      // A (1) -> 10
        bne !++
!:      and #$0f
!:      sta ed_hex_buf,x
        inx
        cpx #4
        bne !---
        lda ed_hex_buf
        asl
        asl
        asl
        asl
        ora ed_hex_buf + 1
        tay
        lda ed_hex_buf + 2
        asl
        asl
        asl
        asl
        ora ed_hex_buf + 3
        tax
        clc
        rts

// A/X = hi/lo: print $hhll
ui_puthex16:
        pha
        lda #SC_DOLLAR
        jsr ui_putc
        pla
        jsr ui_puthex
        txa
ui_puthex:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr uh_nibble
        pla
        and #$0f
uh_nibble:
        stx ed_digit
        tax
        lda uh_digits,x
        jsr ui_putc
        ldx ed_digit
        rts
uh_digits:
        .encoding "screencode_upper"
        .text "0123456789ABCDEF"

// ---- save with a linked program --------------------------------------------
// command channel stays open, dest LFN_OUT (SA 1 = write PRG), source
// LFN_FILE. Leaves the drive status in ed_status_buf.
link_save:
        lda #0
        jsr SETNAM
        lda #LFN_CMD
        ldx ed_dev
        ldy #SA_CMD
        jsr SETLFS
        jsr OPEN
        lda ed_link_name_len        // source first: no half file on errors
        ldx #<ed_link_name
        ldy #>ed_link_name
        jsr SETNAM
        lda #LFN_FILE
        ldx ed_dev
        ldy #SA_READ
        jsr SETLFS
        jsr OPEN
        jsr lk_status_ok            // e.g. 62, FILE NOT FOUND
        bcc !+
        jmp lk_close
!:
        lda ed_fname_len
        ldx #<ed_fname
        ldy #>ed_fname
        jsr SETNAM
        lda #LFN_OUT
        ldx ed_dev
        ldy #SA_WRITE
        jsr SETLFS
        jsr OPEN
        jsr lk_status_ok            // e.g. 63, FILE EXISTS
        bcc !+
        jmp lk_close
!:
        ldx #LFN_OUT
        jsr CHKOUT
        lda #<BASIC_START           // load address
        jsr CHROUT
        lda #>BASIC_START
        jsr CHROUT
        lda #<BASIC_START           // intro $0801-$3fff
        sta ed_ptr
        lda #>BASIC_START
        sta ed_ptr + 1
        lda #<(LINK_MOVER - BASIC_START)
        sta ed_t0
        lda #>(LINK_MOVER - BASIC_START)
        sta ed_t1
        jsr lk_write
        lda #<ed_mover              // mover
        sta ed_ptr
        lda #>ed_mover
        sta ed_ptr + 1
        lda #<MOVER_SIZE
        sta ed_t0
        lda #>MOVER_SIZE
        sta ed_t1
        jsr lk_write
        jsr CLRCHN
        ldx #LFN_FILE               // program data
        jsr CHKIN
        jsr CHRIN                   // skip the load address
        jsr CHRIN
lk_chunk:
        ldx #LFN_FILE
        jsr CHKIN
        lda #<FILE_BUF
        sta ed_ptr
        lda #>FILE_BUF
        sta ed_ptr + 1
!:      jsr READST
        bne !+                      // EOF (or error) before this byte
        jsr CHRIN
        ldy #0
        sta (ed_ptr),y
        inc ed_ptr
        bne !-
        inc ed_ptr + 1
        lda ed_ptr + 1
        cmp #>FILE_BUF_END
        bne !-
!:      lda ed_ptr                  // bytes in this chunk
        sta ed_t0
        lda ed_ptr + 1
        sec
        sbc #>FILE_BUF
        sta ed_t1
        jsr READST
        sta ed_t3
        jsr CLRCHN
        ldx #LFN_OUT
        jsr CHKOUT
        lda #<FILE_BUF
        sta ed_ptr
        lda #>FILE_BUF
        sta ed_ptr + 1
        jsr lk_write
        jsr CLRCHN
        lda ed_t3
        beq lk_chunk                // buffer full, more to come
lk_close:
        jsr CLRCHN
        lda #LFN_FILE
        jsr CLOSE
        lda #LFN_OUT
        jsr CLOSE
        jsr ed_status_clear
        ldx #0
        jsr drs_read_open           // final status, then close 15
        lda #LFN_CMD
        jmp CLOSE

// write ed_t0/1 bytes from (ed_ptr) to the current output
lk_write:
        lda ed_t0
        ora ed_t1
        beq lw_done
        ldy #0
        lda (ed_ptr),y
        jsr CHROUT
        inc ed_ptr
        bne !+
        inc ed_ptr + 1
!:      lda ed_t0
        bne !+
        dec ed_t1
!:      dec ed_t0
        jmp lk_write
lw_done:
        rts

// read the command channel; carry set unless the status starts with "00"
lk_status_ok:
        jsr ed_status_clear
        ldx #0
        jsr drs_read_open
        lda ed_status_buf
        cmp #SC_DIGIT_0
        bne !+
        lda ed_status_buf + 1
        cmp #SC_DIGIT_0
        bne !+
        clc
        rts
!:      sec
        rts

// ---- mover (runs at MOVER_ADDR, parameters in MV_*) -------------------------
ed_mover:
.pseudopc MOVER_ADDR {
        lda MV_START                // RUN: start via mv_run
        ora MV_START + 1
        bne !+
        lda #<mv_run
        sta MV_START
        lda #>mv_run
        sta MV_START + 1
!:      lda MV_START
        sta mv_jmp + 1
        lda MV_START + 1
        sta mv_jmp + 2
        clc                         // end = dest + len (BASIC VARTAB)
        lda MV_DEST
        adc MV_LEN
        sta mv_end_lo + 1
        lda MV_DEST + 1
        adc MV_LEN + 1
        sta mv_end_hi + 1
        ldx MV_LEN + 1              // full pages
        ldy #0
        lda MV_DEST                 // MV_SRC / MV_DEST are the pointers
        cmp MV_SRC
        lda MV_DEST + 1
        sbc MV_SRC + 1
        bcc mv_fwd                  // dest < src: forwards
        txa                         // backwards: top block first
        clc
        adc MV_SRC + 1
        sta MV_SRC + 1
        txa
        clc
        adc MV_DEST + 1
        sta MV_DEST + 1
        ldy MV_LEN
        beq mv_bpage
!:      dey
        lda (MV_SRC),y
        sta (MV_DEST),y
        tya
        bne !-
mv_bpage:
        txa
        beq mv_done
        dex
        dec MV_SRC + 1
        dec MV_DEST + 1
!:      dey
        lda (MV_SRC),y
        sta (MV_DEST),y
        tya
        bne !-
        beq mv_bpage
mv_fwd:
        txa
        beq mv_fpart
!:      lda (MV_SRC),y
        sta (MV_DEST),y
        iny
        bne !-
        inc MV_SRC + 1
        inc MV_DEST + 1
        dex
        bne !-
mv_fpart:
        ldx MV_LEN
        beq mv_done
!:      lda (MV_SRC),y
        sta (MV_DEST),y
        iny
        dex
        bne !-
mv_done:
        ldx #ZP_RT_END - ZP_RT_START - 1
!:      lda RT_ZP_SAVE,x            // BASIC's zero page back
        sta ZP_RT_START,x
        dex
        bpl !-
        lda #CPU_DEFAULT
        sta CPU_PORT
        jsr IOINIT
        jsr RESTOR
        jsr CINT
mv_end_lo:
        lda #0
        sta VARTAB
mv_end_hi:
        lda #0
        sta VARTAB + 1
        cli
mv_jmp:
        jmp mv_run
mv_run:
        jsr BASIC_RUN_INIT
        jmp BASIC_NEWSTT
}
.errorif (FILE_BUF & $ff) != 0, "link_save assumes a page aligned FILE_BUF"
.errorif * - ed_mover > MOVER_SIZE, "mover too large: " + (* - ed_mover)
        .fill MOVER_SIZE - (* - ed_mover), 0

str_link:       Str("LINK PROGRAM")
str_l_prog:     Str("1 PROGRAM")
str_l_start:    Str("2 START")
str_l_sys:      Str("3 SYS ADDRESS")
str_l_remove:   Str("4 REMOVE")
str_l_none:     Str("NONE")
str_l_run:      Str("RUN")
str_l_sys_at:   Str("SYS ")
str_l_load:     Str("LOADS TO ")
str_l_verify:   Str("MEASURING PROGRAM...")
str_l_bad:      Str("PROGRAM DOES NOT FIT ($0400-$CFFF, 36 KB)")
str_hint_link:  Str("1-4 CHANGE  STOP BACK")
