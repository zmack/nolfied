ROM    := build/nolfied.sfc
ASSETS := build/bgtiles.bin build/icons.bin

all: $(ROM)

build/bgtiles.bin: tools/gen_assets.py
	python3 tools/gen_assets.py build

build/icons.bin: tools/gen_icons.py
	python3 tools/gen_icons.py build

build/main.o: src/main.s $(ASSETS)
	ca65 -g --cpu 65816 --bin-include-dir build -o $@ src/main.s

$(ROM): build/main.o src/snes.cfg tools/fix_checksum.py Makefile
	ld65 -C src/snes.cfg -Ln build/nolfied.lbl -o $@ build/main.o
	python3 tools/fix_checksum.py $@

# assembly benchmark ROM for the C trial (experiments/c-trial)
bench: build/nolfied_bench.sfc
	$(MAKE) -C experiments/c-trial
	python3 tools/bench_score.py

build/nolfied_bench.sfc: src/main.s $(ASSETS) experiments/c-trial/vectors.bin
	ca65 -g --cpu 65816 -D BENCH --bin-include-dir build --bin-include-dir experiments/c-trial \
	     -o build/main_bench.o src/main.s
	ld65 -C src/snes.cfg -Ln build/nolfied_bench.lbl -o $@ build/main_bench.o
	python3 tools/fix_checksum.py $@

experiments/c-trial/bench.sfc experiments/c-trial/vectors.bin:
	$(MAKE) -C experiments/c-trial

test: $(ROM)
	python3 tools/test_flow.py
	python3 tools/test_perks.py

tla:
	spec/check.sh

run: $(ROM)
	mame snes -cart $(ROM) -window

clean:
	rm -rf build

.PHONY: all run clean test tla bench
