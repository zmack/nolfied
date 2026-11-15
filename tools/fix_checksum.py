#!/usr/bin/env python3
"""Write the SNES internal header checksum (LoROM, header at $7FC0)."""
import sys

path = sys.argv[1]
rom = bytearray(open(path, "rb").read())
assert len(rom) & (len(rom) - 1) == 0, "ROM size must be a power of two"
rom[0x7FDC:0x7FE0] = b"\xff\xff\x00\x00"
ck = sum(rom) & 0xFFFF
cpl = ck ^ 0xFFFF
rom[0x7FDC] = cpl & 0xFF
rom[0x7FDD] = cpl >> 8
rom[0x7FDE] = ck & 0xFF
rom[0x7FDF] = ck >> 8
open(path, "wb").write(rom)
print(f"{path}: {len(rom)//1024}KB checksum ${ck:04X}")
