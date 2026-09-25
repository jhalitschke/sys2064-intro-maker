#importonce
// ---------------------------------------------------------------------------
// vars.asm - editor variables at ED_VARS (not part of the program file).
// ---------------------------------------------------------------------------
* = ED_VARS "editor vars" virtual
ed_dev:         .byte 0             // drive number
ed_music_on:    .byte 0             // 1 = editor IRQ calls play
ed_text_len:    .word 0             // scroll text length (without $ff)
ed_cur:         .word 0             // scroll text cursor
ed_win:         .word 0             // scroll text window start
ed_title_cur:   .byte 0             // title cursor 0-79
ed_list_kind:   .byte 0             // 0 = music, 1 = font
ed_list_sel:    .byte 0
ed_list_n:      .byte 0
ed_music_name:  .fill CAT_NAME_LEN, 0
ed_font_name:   .fill CAT_NAME_LEN, 0
ed_fname_len:   .byte 0
ed_fname:       .fill FNAME_MAX, 0
ed_status_buf:  .fill SCREEN_COLS, 0
ed_list_top:    .byte 0             // first visible list entry
ed_dir_n:       .byte 0             // PRG files in DIR_NAMES
ed_file_len:    .byte 0             // picked file name
ed_file_name_buf: .fill DIR_NAME_LEN, 0
ed_buf_len:     .word 0             // bytes in FILE_BUF
ed_load:        .word 0             // tune being checked
ed_init:        .word 0
ed_play:        .word 0
ed_sub:         .byte 0
.errorif ed_font_name != ed_music_name + CAT_NAME_LEN, "name buffers must be adjacent"
.errorif * > ED_VARS_END, "editor variables overflow"
