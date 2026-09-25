// ---------------------------------------------------------------------------
// testtune.asm - own test tune: short arpeggio loop on voice 1.
// Load $1000, init $1000, play $1003 (once per PAL frame).
// ---------------------------------------------------------------------------
#import "../../src/shared/memmap.asm"

.const PAL_CLOCK     = 985248
.const ARP_FRAMES    = 2            // frames per arpeggio note
.const CHORD_FRAMES  = 48           // frames per chord
.const CHORD_COUNT   = 4
.const CHORD_NOTES   = 3
.const WAVE_PULSE    = $40
.const GATE          = $01
.const AD_VALUE      = $09
.const SR_VALUE      = $a8
.const PW_HI_VALUE   = $08
.const VOLUME_MAX    = $0f

.function sidFreq(note) {
    .return round(440 * pow(2, (note - 69) / 12) * 16777216 / PAL_CLOCK)
}

* = SID_START "testtune"
        jmp tt_init
        jmp tt_play

tt_init:
        lda #0
        ldx #SID_REGS - 1
!:      sta SID_BASE,x
        dex
        bpl !-
        sta tt_tick
        sta tt_arp
        sta tt_chord
        sta tt_chord_tick
        lda #VOLUME_MAX
        sta SID_VOLUME
        lda #AD_VALUE
        sta SID_V1_AD
        lda #SR_VALUE
        sta SID_V1_SR
        lda #PW_HI_VALUE
        sta SID_V1_PW_HI
        jsr tt_note
        lda #WAVE_PULSE | GATE
        sta SID_V1_CTRL
        rts

tt_play:
        inc tt_chord_tick
        lda tt_chord_tick
        cmp #CHORD_FRAMES
        bne tt_arp_step
        // next chord: retrigger gate
        lda #0
        sta tt_chord_tick
        sta tt_arp
        sta tt_tick
        lda tt_chord
        clc
        adc #1
        and #CHORD_COUNT - 1
        sta tt_chord
        lda #WAVE_PULSE
        sta SID_V1_CTRL
        jsr tt_note
        lda #WAVE_PULSE | GATE
        sta SID_V1_CTRL
        rts

tt_arp_step:
        inc tt_tick
        lda tt_tick
        cmp #ARP_FRAMES
        bne tt_done
        lda #0
        sta tt_tick
        ldx tt_arp
        inx
        cpx #CHORD_NOTES
        bne !+
        ldx #0
!:      stx tt_arp
        jsr tt_note
tt_done:
        rts

// set voice 1 frequency to chord[tt_chord], note tt_arp
tt_note:
        lda tt_chord
        asl
        adc tt_chord                // * 3 (carry clear: chord < 4)
        adc tt_arp
        tax
        ldy tt_notes,x
        lda tt_freq_lo,y
        sta SID_V1_FREQ_LO
        lda tt_freq_hi,y
        sta SID_V1_FREQ_HI
        rts

// Am, F, C, G (MIDI notes)
.var chordNotes = List().add(57, 60, 64,  53, 57, 60,  60, 64, 67,  55, 59, 62)
tt_notes:
        .fill chordNotes.size(), i
tt_freq_lo:
        .fill chordNotes.size(), <sidFreq(chordNotes.get(i))
tt_freq_hi:
        .fill chordNotes.size(), >sidFreq(chordNotes.get(i))

tt_tick:        .byte 0
tt_arp:         .byte 0
tt_chord:       .byte 0
tt_chord_tick:  .byte 0

.errorif * > SID_END, "test tune too large"
