#importonce
// ---------------------------------------------------------------------------
// disk.asm - LOAD, SAVE, drive status (M4). M3: no disk access yet.
// ---------------------------------------------------------------------------

disk_load_catalog:
        rts

// ed_ptr = catalog record: load its file. Carry set on error.
disk_load_rec:
        sec
        rts

ed_save:
        rts
