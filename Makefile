ROM    := build/nolfied.sfc
ASSETS := build/bgtiles.bin

all: $(ROM)

$(ASSETS): tools/gen_assets.py
	python3 tools/gen_assets.py build

build/main.o: src/main.s $(ASSETS)
	ca65 -g --cpu 65816 --bin-include-dir build -o $@ src/main.s

$(ROM): build/main.o src/snes.cfg tools/fix_checksum.py Makefile
	ld65 -C src/snes.cfg -Ln build/nolfied.lbl -o $@ build/main.o
	python3 tools/fix_checksum.py $@

run: $(ROM)
	mame snes -cart $(ROM) -window

clean:
	rm -rf build

.PHONY: all run clean
