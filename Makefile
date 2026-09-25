# C64 Intro Maker - build (see docs/SPEC.md, section 9)

KICKASS  ?= kickass
X64      ?= x64sc
C1541    ?= c1541
PYTHON   ?= python3
EXOMIZER ?= exomizer

BUILD     := build
ABS_BUILD := $(abspath $(BUILD))
XVFB      := $(if $(DISPLAY),,xvfb-run -a)
KFLAGS    := -odir $(ABS_BUILD)
SRC       := $(shell find src -name '*.asm')

# Optional fixture config override, e.g. make fixture FIXTURE_FLAGS=5
FIXTURE_FLAGS ?=
FIXTURE_ARGS  := $(if $(FIXTURE_FLAGS),:flags=$(FIXTURE_FLAGS),)

VICE_SMOKE := -default -pal -warp -sounddev dummy

.PHONY: all disk fixture run run-fixture test smoke clean

all: disk
disk: $(BUILD)/intromaker.d64

$(BUILD):
	mkdir -p $@

$(BUILD)/testtune.prg: assets/testtune/testtune.asm src/shared/memmap.asm | $(BUILD)
	$(KICKASS) $< $(KFLAGS) -o $(abspath $@)

$(BUILD)/editor.prg: $(SRC) | $(BUILD)
	$(KICKASS) src/main.asm $(KFLAGS) -o $(abspath $@)

$(BUILD)/intromaker.d64: $(BUILD)/editor.prg $(BUILD)/testtune.prg assets/manifest.toml tools/build_disk.py
	$(PYTHON) tools/build_disk.py --editor $(BUILD)/editor.prg --out $@ --c1541 $(C1541)

fixture: $(BUILD)/testtune.prg
	$(KICKASS) src/main.asm -define FIXTURE $(FIXTURE_ARGS) $(KFLAGS) -o $(ABS_BUILD)/fixture.prg

run: disk
	$(X64) -autostart $(BUILD)/intromaker.d64

run-fixture: fixture
	$(X64) -autostartprgmode 1 -autostart $(BUILD)/fixture.prg

test:
	$(PYTHON) -m unittest discover tools

# VICE exits with an error code when -limitcycles hits: ignore it (leading -).
smoke: fixture disk
	rm -f $(BUILD)/fixture.png $(BUILD)/editor.png
	-$(XVFB) $(X64) $(VICE_SMOKE) -limitcycles 20000000 \
	    -exitscreenshot $(BUILD)/fixture.png -autostartprgmode 1 -autostart $(BUILD)/fixture.prg
	-$(XVFB) $(X64) $(VICE_SMOKE) -limitcycles 40000000 \
	    -exitscreenshot $(BUILD)/editor.png -autostart $(BUILD)/intromaker.d64
	test -f $(BUILD)/fixture.png && test -f $(BUILD)/editor.png

clean:
	rm -rf $(BUILD)
