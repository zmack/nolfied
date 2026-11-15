# NOLFIED: C game (Calypsi 65816) with a small assembly core.
#   make          build/nolfied.sfc + build/nolfied.lbl
#   make test     flow test + perk tests       make tla     TLA+ models
#   make legacy   the original all-assembly ROM (legacy/, ca65)
#   make bench    C vs legacy scoring benchmark

ROM     := build/nolfied.sfc
ASSETS  := build/bgtiles.bin build/icons.bin
CC      := cc65816
AS      := as65816
LD      := ln65816
CFLAGS  := --code-model=small --data-model=small -O2 --speed -I src
CSRC    := $(wildcard src/*.c)
OBJS    := $(CSRC:src/%.c=build/%.o) build/core.o build/header.o
HEADERS := $(wildcard src/*.h)

all: $(ROM)

build/bgtiles.bin: tools/gen_assets.py
	python3 tools/gen_assets.py build

build/icons.bin: tools/gen_icons.py
	python3 tools/gen_icons.py build

# no --target=SNES: Calypsi 5.18 miscompiles hardware multiplies with it
# (experiments/c-trial/README.md); hw.h drives the multiplier by hand instead.
build/%.o: src/%.c $(HEADERS) | $(ASSETS)
	$(CC) $(CFLAGS) -l --list-file build/$*.lst -o $@ $<

build/core.o: src/core.s $(ASSETS)
	cd build && $(AS) -l --list-file core.lst ../src/core.s -o core.o

build/header.o: src/header.s
	$(AS) src/header.s -o $@

$(ROM): $(OBJS) src/nolfied.scm tools/hirom_fix.py tools/calypsi_lbl.py
	$(LD) src/nolfied.scm $(OBJS) -o build/nolfied.elf --output-format raw \
	      --rtattr exit=simplified --stack-size 1024 \
	      -l --list-file build/nolfied.lst --cross-reference
	python3 tools/hirom_fix.py build/nolfied.raw $@
	python3 tools/calypsi_lbl.py build/nolfied.lst build/nolfied.lbl

# ---- the original all-assembly version ------------------------------------
LEGACY := build/legacy/nolfied.sfc
legacy: $(LEGACY)
$(LEGACY): legacy/main.s legacy/snes.cfg $(ASSETS)
	mkdir -p build/legacy
	ca65 -g --cpu 65816 --bin-include-dir build -o build/legacy/main.o legacy/main.s
	ld65 -C legacy/snes.cfg -Ln build/legacy/nolfied.lbl -o $@ build/legacy/main.o
	python3 tools/fix_checksum.py $@

# assembly benchmark ROM for the C trial (experiments/c-trial)
bench: build/legacy/nolfied_bench.sfc
	$(MAKE) -C experiments/c-trial
	python3 tools/bench_score.py

build/legacy/nolfied_bench.sfc: legacy/main.s $(ASSETS) experiments/c-trial/vectors.bin
	mkdir -p build/legacy
	ca65 -g --cpu 65816 -D BENCH --bin-include-dir build --bin-include-dir experiments/c-trial \
	     -o build/legacy/main_bench.o legacy/main.s
	ld65 -C legacy/snes.cfg -Ln build/legacy/nolfied_bench.lbl -o $@ build/legacy/main_bench.o
	python3 tools/fix_checksum.py $@

experiments/c-trial/bench.sfc experiments/c-trial/vectors.bin:
	$(MAKE) -C experiments/c-trial

# the assembly core must still match the legacy routines it came from
verify-port: $(LEGACY) build/core.o
	python3 tools/verify_port.py

test: $(ROM)
	python3 tools/test_flow.py
	python3 tools/test_perks.py

tla:
	spec/check.sh

run: $(ROM)
	mame snes -cart $(ROM) -window

clean:
	rm -rf build

.PHONY: all run clean test tla bench legacy verify-port
