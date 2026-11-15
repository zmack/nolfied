# Calypsi C trial: the perk/scoring module in C, plus a benchmark ROM.
CC      = cc65816
AS      = as65816
LD      = ln65816
# --target=SNES is NOT used: Calypsi 5.18 miscompiles 8x8 hardware multiplies
# with a stack operand on that target (see README.md). Generic 65816 code
# runs fine on the SNES; it just uses a software multiply.
CFLAGS  = --code-model=small --data-model=small -O2 --speed --always-inline
RULES   = /usr/local/lib/calypsi-65816/linker-rules/snes-HiROM.scm
OBJS    = bench.o score.o perks.o header.o

all: bench.sfc

vectors.h vectors.bin: gen_vectors.py
	python3 gen_vectors.py vectors.bin vectors.h

bench.o: bench.c vectors.h score.h perks.h perk_defs.h
score.o perks.o: perks.h perk_defs.h hw_math.h
%.o: %.c
	$(CC) $(CFLAGS) $< -o $@
%.o: %.s
	$(AS) $< -o $@

bench.sfc: $(OBJS)
	$(LD) $(RULES) $(OBJS) -o bench.elf --output-format raw \
	      --rtattr exit=simplified -l --cross-reference
	python3 hirom_fix.py bench.raw $@

clean:
	rm -f *.o *.elf *.raw *.lst bench.sfc vectors.h vectors.bin

.PHONY: all clean
