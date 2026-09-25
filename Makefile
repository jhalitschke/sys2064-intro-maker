# C64 Intro Maker - build (see docs/SPEC.md, section 9)

KICKASS  ?= kickass
X64      ?= x64sc
C1541    ?= c1541
PYTHON   ?= python3
EXOMIZER ?= exomizer
MANIFEST ?= assets/manifest.toml

BUILD     := build
ABS_BUILD := $(abspath $(BUILD))
# always headless: VICE windows (and XTEST key presses in e2e) must never
# reach the real desktop
XVFB      := xvfb-run -a
KFLAGS    := -odir $(ABS_BUILD)
SRC       := $(shell find src -name '*.asm')

# Optional fixture config override, e.g. make fixture FIXTURE_FLAGS=5
FIXTURE_FLAGS ?=
FIXTURE_ARGS  := $(if $(FIXTURE_FLAGS),:flags=$(FIXTURE_FLAGS),)

VICE_SMOKE := -default -pal -warp -sounddev dummy

.PHONY: all disk fixture run run-fixture test smoke e2e clean

all: disk
disk: $(BUILD)/intromaker.d64

$(BUILD):
	mkdir -p $@

$(BUILD)/testtune.prg: assets/testtune/testtune.asm src/shared/memmap.asm | $(BUILD)
	$(KICKASS) $< $(KFLAGS) -o $(abspath $@)

$(BUILD)/editor.prg: $(SRC) | $(BUILD)
	$(KICKASS) src/main.asm $(KFLAGS) -o $(abspath $@)
	cp $(BUILD)/main.sym $(BUILD)/editor.sym

# packed editor: self-extracting, starts via the SYS line of the stub
$(BUILD)/editor.exo.prg: $(BUILD)/editor.prg
	$(EXOMIZER) sfx sys -n -q -o $@ $<

$(BUILD)/intromaker.d64: $(BUILD)/editor.exo.prg $(BUILD)/testtune.prg $(MANIFEST) tools/build_disk.py
	$(PYTHON) tools/build_disk.py --manifest $(MANIFEST) --editor $(BUILD)/editor.exo.prg --out $@ --c1541 $(C1541)

fixture: $(BUILD)/testtune.prg
	$(KICKASS) src/main.asm -define FIXTURE $(FIXTURE_ARGS) $(KFLAGS) -o $(ABS_BUILD)/fixture.prg
	cp $(BUILD)/main.sym $(BUILD)/fixture.sym

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

# End-to-end tests in VICE with real key presses (needs python-xlib), ~10 min.
# Single file: make e2e E2E=test_editor
E2E ?= test_*
e2e: disk fixture
	E2E_HEADLESS=1 $(XVFB) $(PYTHON) -m unittest discover -s tests/e2e -t tests/e2e -p '$(E2E).py' -v

clean:
	rm -rf $(BUILD)
