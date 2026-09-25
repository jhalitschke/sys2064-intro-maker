#importonce
// ---------------------------------------------------------------------------
// files.asm - read files and the directory into FILE_BUF, convert tunes
// (PSID or PRG at $1000) and fonts loaded from any disk.
// ---------------------------------------------------------------------------

// A = name length, X/Y = name: read the whole file (incl. its load
// address) into FILE_BUF, ed_buf_len = length. Carry set on error (status
// line shows LOAD ERROR + drive status). The music keeps playing.
disk_read:
        jsr SETNAM
        lda #LFN_FILE
        ldx ed_dev
        ldy #SA_READ
        jsr SETLFS
        jsr OPEN
        bcs dr_fail
        ldx #LFN_FILE
        jsr CHKIN
        bcs dr_fail
        lda #<FILE_BUF
        sta ed_ptr2
        lda #>FILE_BUF
        sta ed_ptr2 + 1
dr_loop:
        jsr CHRIN
        ldy #0
        sta (ed_ptr2),y
        jsr READST
        sta ed_t0
        and #ST_ERRORS              // timeout / device not present
        bne dr_fail                 // (a missing file times out)
        inc ed_ptr2
        bne !+
        inc ed_ptr2 + 1
!:      lda ed_ptr2 + 1
        cmp #>FILE_BUF_END
        beq dr_too_large
        lda ed_t0
        and #ST_EOF
        beq dr_loop
        jsr dr_close
        lda ed_ptr2
        sec
        sbc #<FILE_BUF
        sta ed_buf_len
        lda ed_ptr2 + 1
        sbc #>FILE_BUF
        sta ed_buf_len + 1
        clc
        rts
dr_too_large:
        jsr dr_close
        lda #<str_err_too_large
        ldy #>str_err_too_large
        jsr ed_status_set
        sec
        rts
dr_fail:
        jsr dr_close
        lda #<str_load_error
        ldy #>str_load_error
        jsr ed_status_set
        jsr disk_read_status
        sec
        rts
dr_close:
        jsr CLRCHN
        lda #LFN_FILE
        jmp CLOSE
.errorif (FILE_BUF_END & $ff) != 0, "FILE_BUF_END must be page aligned"

// read the file ed_file_name_buf / ed_file_len
disk_read_file:
        lda ed_file_len
        ldx #<ed_file_name_buf
        ldy #>ed_file_name_buf
        jmp disk_read

// ---- directory ---------------------------------------------------------------
// LOAD"$" listing -> DIR_NAMES / DIR_LENS (PRG files only), ed_dir_n
disk_read_dir:
        lda #1
        ldx #<str_dollar
        ldy #>str_dollar
        jsr disk_read
        bcc !+
        rts
!:      lda #0
        sta ed_dir_n
        lda #<(FILE_BUF + 2)        // skip the load address
        sta ed_ptr2
        lda #>(FILE_BUF + 2)
        sta ed_ptr2 + 1
        jsr dd_line_start           // header line (disk name)
        beq dd_done
        jsr dd_skip_line
dd_line:
        jsr dd_line_start
        beq dd_done
        // find the opening quote
!:      jsr dd_get
        beq dd_skip                 // no name in this line (BLOCKS FREE)
        cmp #PET_QUOTE
        bne !-
        lda ed_dir_n
        cmp #DIR_MAX
        bcs dd_done
        jsr dir_name_ptr            // ed_ptr = name slot
        ldy #0
        sty ed_t1                   // name length
!:      jsr dd_get
        beq dd_skip
        cmp #PET_QUOTE
        beq !+
        ldy ed_t1
        cpy #DIR_NAME_LEN
        bcs !-
        sta (ed_ptr),y
        inc ed_t1
        bne !-
!:      jsr dd_get                  // skip spaces up to the type
        beq dd_skip
        cmp #SC_SPACE
        beq !-
        cmp #PET_P                  // "PRG" (a splat file starts with "*")
        bne dd_skip
        jsr dd_get
        cmp #PET_R
        bne dd_skip
        jsr dd_get
        cmp #PET_G
        bne dd_skip
        ldx ed_dir_n
        lda ed_t1
        sta DIR_LENS,x
        beq dd_skip                 // empty name
        inc ed_dir_n
dd_skip:
        jsr dd_skip_line
        jmp dd_line
dd_done:
        clc
        rts

// start of a listing line: Z set at the end of the listing, else the
// pointer is moved behind link and line number
dd_line_start:
        ldy #0
        lda (ed_ptr2),y
        iny
        ora (ed_ptr2),y
        beq dls_done
        lda ed_ptr2
        clc
        adc #4
        sta ed_ptr2
        bcc !+
        inc ed_ptr2 + 1
!:      lda #1                      // Z clear
dls_done:
        rts

// next byte of the line -> A (Z set at the line end, pointer stays there)
dd_get:
        ldy #0
        lda (ed_ptr2),y
        beq dg_done
        inc ed_ptr2
        bne !+
        inc ed_ptr2 + 1
!:      tay                         // Z from the byte again
dg_done:
        rts

// move behind the 0 that ends the current line
dd_skip_line:
!:      jsr dd_get
        bne !-
        inc ed_ptr2
        bne !+
        inc ed_ptr2 + 1
!:      rts

// A = directory index -> ed_ptr = DIR_NAMES + 16 * A
dir_name_ptr:
        sta ed_ptr
        lda #0
        sta ed_ptr + 1
        ldx #4
!:      asl ed_ptr
        rol ed_ptr + 1
        dex
        bne !-
        lda ed_ptr
        clc
        adc #<DIR_NAMES
        sta ed_ptr
        lda ed_ptr + 1
        adc #>DIR_NAMES
        sta ed_ptr + 1
        rts

// ---- tunes -------------------------------------------------------------------
// FILE_BUF holds a PSID file or a PRG at $1000. On success the music is
// stopped, the data copied to SID_START, init/play/subtune and the name set.
// Carry set on error (status line), the old tune is untouched then.
sid_from_buffer:
        jsr sfb_is_psid
        beq !+
        jmp sfb_not_psid
!:
        // PSID header (big endian)
        lda FILE_BUF + PSID_DATA + 1
        clc
        adc #<FILE_BUF
        sta ed_ptr
        lda FILE_BUF + PSID_DATA
        adc #>FILE_BUF
        sta ed_ptr + 1
        lda ed_buf_len              // length = buf_len - data offset
        sec
        sbc FILE_BUF + PSID_DATA + 1
        sta ed_t0
        lda ed_buf_len + 1
        sbc FILE_BUF + PSID_DATA
        sta ed_t1
        lda FILE_BUF + PSID_LOAD + 1
        sta ed_load
        lda FILE_BUF + PSID_LOAD
        sta ed_load + 1
        ora ed_load
        bne !+
        jsr sfb_embedded_load       // load 0: address in the data
!:      lda FILE_BUF + PSID_INIT + 1
        sta ed_init
        lda FILE_BUF + PSID_INIT
        sta ed_init + 1
        ora ed_init
        bne !+
        lda ed_load                 // init 0 = load
        sta ed_init
        lda ed_load + 1
        sta ed_init + 1
!:      lda FILE_BUF + PSID_PLAY + 1
        sta ed_play
        lda FILE_BUF + PSID_PLAY
        sta ed_play + 1
        ldx FILE_BUF + PSID_START + 1
        beq !+
        dex                         // start song is 1 based
!:      stx ed_sub
        // speed bit of the subtune set: CIA timing (songs > 32 use bit 31)
        txa
        cpx #PSID_SPEED_BITS
        bcc !+
        lda #PSID_SPEED_BITS - 1
!:      pha
        lsr
        lsr
        lsr
        eor #3                      // big endian byte index
        tax
        pla
        and #7
        tay
        lda FILE_BUF + PSID_SPEED,x
!:      dey
        bmi !+
        lsr
        jmp !-
!:      and #1
        beq sfb_check
        lda #<str_err_cia
        ldy #>str_err_cia
        jmp sfb_error
sfb_not_psid:
        ldx #3
!:      lda FILE_BUF,x
        cmp str_rsid,x
        bne sfb_prg
        dex
        bpl !-
        lda #<str_err_rsid
        ldy #>str_err_rsid
        jmp sfb_error
sfb_prg:
        lda FILE_BUF                // PRG: load address, $1000/$1003
        sta ed_load
        lda FILE_BUF + 1
        sta ed_load + 1
        lda #<(FILE_BUF + 2)
        sta ed_ptr
        lda #>(FILE_BUF + 2)
        sta ed_ptr + 1
        lda ed_buf_len
        sec
        sbc #2
        sta ed_t0
        lda ed_buf_len + 1
        sbc #0
        sta ed_t1
        lda #<DEF_INIT
        sta ed_init
        lda #>DEF_INIT
        sta ed_init + 1
        lda #<DEF_PLAY
        sta ed_play
        lda #>DEF_PLAY
        sta ed_play + 1
        lda #DEF_SUBTUNE
        sta ed_sub
sfb_check:
        lda ed_load
        cmp #<SID_START
        bne sfb_addr
        lda ed_load + 1
        cmp #>SID_START
        bne sfb_addr
        lda ed_t0                   // 0 < length <= 4 KB
        ora ed_t1
        beq sfb_size
        lda #<(SID_END - SID_START)
        cmp ed_t0
        lda #>(SID_END - SID_START)
        sbc ed_t1
        bcc sfb_size
        lda ed_play
        ora ed_play + 1
        beq sfb_range
        lda ed_init                 // init/play inside $1000..$1000+len
        ldx ed_init + 1
        jsr sfb_in_data
        bcs sfb_range
        lda ed_play
        ldx ed_play + 1
        jsr sfb_in_data
        bcs sfb_range
        // accepted: copy
        jsr ed_music_stop
        lda #<SID_START
        sta ed_ptr2
        lda #>SID_START
        sta ed_ptr2 + 1
        jsr mem_copy_down
        lda ed_init
        sta cfg_init
        lda ed_init + 1
        sta cfg_init + 1
        lda ed_play
        sta cfg_play
        lda ed_play + 1
        sta cfg_play + 1
        lda ed_sub
        sta cfg_subtune
        jsr sfb_name
        clc
        rts
sfb_addr:
        lda #<str_err_addr
        ldy #>str_err_addr
        jmp sfb_error
sfb_size:
        lda #<str_err_size
        ldy #>str_err_size
        jmp sfb_error
sfb_range:
        lda #<str_err_range
        ldy #>str_err_range
sfb_error:
        jsr ed_status_set
        sec
        rts

// load address 0: the first two data bytes hold it
sfb_embedded_load:
        ldy #0
        lda (ed_ptr),y
        sta ed_load
        iny
        lda (ed_ptr),y
        sta ed_load + 1
        lda ed_ptr
        clc
        adc #2
        sta ed_ptr
        bcc !+
        inc ed_ptr + 1
!:      lda ed_t0
        sec
        sbc #2
        sta ed_t0
        bcs !+
        dec ed_t1
!:      rts

// A/X = address: carry clear if SID_START <= address < SID_START + len
sfb_in_data:
        sta ed_t2
        stx ed_t3
        cpx #>SID_START
        bcc !+                      // below $1000
        lda ed_t2
        sec
        sbc #<SID_START
        tax
        lda ed_t3
        sbc #>SID_START             // offset in A/X (hi/lo)
        sta ed_t3
        cpx ed_t0                   // offset < length?
        sbc ed_t1
        rts                         // carry clear if offset < length
!:      sec
        rts

// tune name: PSID name field (ASCII) or the file name
sfb_name:
        jsr sfb_is_psid
        bne sfb_file_name
        ldx #0
        ldy #0
!:      lda FILE_BUF + PSID_NAME,y
        beq sfb_pad
        jsr ascii2sc
        sta ed_music_name,x
        inx
        iny
        cpx #CAT_NAME_LEN
        bne !-
        rts
sfb_pad:
        lda #SC_SPACE
!:      sta ed_music_name,x
        inx
        cpx #CAT_NAME_LEN
        bne !-
        rts
sfb_file_name:
        jmp ed_file_name_music

// Z set if FILE_BUF starts with "PSID"
sfb_is_psid:
        ldx #3
!:      lda FILE_BUF,x
        cmp str_psid,x
        bne !+
        dex
        bpl !-
        lda #0
!:      rts

// A = ASCII -> screen code (upper case, unknown -> ?)
ascii2sc:
        cmp #ASCII_LOWER_A
        bcc !+
        cmp #ASCII_LOWER_Z + 1
        bcs a2s_unknown
        sbc #ASCII_LOWER_A - 2      // carry clear: a -> 1
        rts
!:      cmp #PET_LETTERS + 1        // A-Z
        bcc !+
        cmp #ASCII_UPPER_Z + 1
        bcs a2s_unknown
        sbc #PET_LETTERS - 1        // carry clear: A -> 1 (sbc subtracts 1 more)
        rts
!:      cmp #PET_FIRST
        bcc a2s_unknown
        cmp #PET_LETTERS
        bcs a2s_unknown
        rts
a2s_unknown:
        lda #SC_UNKNOWN & SC_MAX
        rts

// ---- fonts -------------------------------------------------------------------
// FILE_BUF holds a font PRG (load address + >= 512 bytes). Carry set on
// error.
font_from_buffer:
        lda ed_buf_len + 1
        cmp #>(FONT_USED_SIZE + 2)
        bcc ffb_short
        bne !+
        lda ed_buf_len
        cmp #<(FONT_USED_SIZE + 2)
        bcc ffb_short
!:      ldx #0
!:      lda FILE_BUF + 2,x
        sta FONT,x
        lda FILE_BUF + 2 + $100,x
        sta FONT + $100,x
        inx
        bne !-
        clc
        rts
ffb_short:
        lda #<str_err_font
        ldy #>str_err_font
        jsr ed_status_set
        sec
        rts
.errorif FONT_USED_SIZE != $200, "font_from_buffer copies two pages"

str_dollar:
        .encoding "petscii_upper"
        .text "$"
str_psid:       .byte $50, $53, $49, $44    // "PSID" (ASCII)
str_rsid:       .byte $52, $53, $49, $44    // "RSID"
str_err_too_large: Str("FILE TOO LARGE")
str_err_rsid:   Str("RSID TUNES ARE NOT SUPPORTED")
str_err_cia:    Str("CIA TIMED TUNES ARE NOT SUPPORTED")
str_err_addr:   Str("TUNE MUST LOAD AT $1000")
str_err_size:   Str("TUNE IS EMPTY OR LARGER THAN 4 KB")
str_err_range:  Str("INIT/PLAY OUTSIDE THE TUNE")
str_err_font:   Str("FONT TOO SHORT (512 BYTES NEEDED)")
