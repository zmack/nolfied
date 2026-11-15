#!/usr/bin/env python3
"""Pad a raw HiROM image to a power of two and write the header checksum."""
import sys
rom = bytearray(open(sys.argv[1], "rb").read())
size = 1 << max(16, (len(rom) - 1).bit_length())
rom += b"\xff" * (size - len(rom))
rom[0xFFD7] = (size // 1024).bit_length() - 1
rom[0xFFDC:0xFFE0] = b"\xff\xff\x00\x00"
ck = sum(rom) & 0xFFFF
rom[0xFFDC:0xFFE0] = bytes([(ck ^ 0xFFFF) & 0xFF, (ck ^ 0xFFFF) >> 8, ck & 0xFF, ck >> 8])
open(sys.argv[2], "wb").write(rom)
print(f"{sys.argv[2]}: {size // 1024}KB checksum ${ck:04X}")
