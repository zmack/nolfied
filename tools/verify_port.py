#!/usr/bin/env python3
"""Check that routines carried over from legacy/main.s (ca65) to src/core.s
(Calypsi) assemble to the same instructions: same opcodes, same lengths.

A width mistake (8-bit vs 16-bit immediate) changes an instruction's length,
so it shows up here even though both assemblers accept the source.

Usage: python3 tools/verify_port.py
       (make verify-port: needs the legacy build and build/core.lst)
"""
import re
import sys

PAIRS = {  # legacy proc -> label in core.s
    "nmi": "nmi", "init_ppu": "init_ppu", "dma_to_vram": "dma_to_vram",
    "dma_to_cgram": "dma_to_cgram", "load_static": "load_static_k",
    "upload_bg1": "upload_bg1_k", "upload_bg3": "upload_bg3_k", "upload_oam": "upload_oam_k",
    "load_picture": "load_picture_k", "init_field": "init_field",
    "update_tile_txy": "update_tile_txy", "update_cell": "update_cell",
    "redraw_all": "redraw_all", "box_scan": "box_scan_k", "spc_init": "spc_init_k",
    "apu_write": "apu_write_k",
}


def legacy_bytes(rom_path, lbl_path):
    """proc -> its exact bytes in the legacy ROM (LoROM: $00:8000 = offset 0),
    using the legacy label file for proc boundaries"""
    rom = open(rom_path, "rb").read()
    labels = {}
    for line in open(lbl_path):
        _, adr, name = line.split()
        labels[name[1:]] = int(adr, 16)
    starts = sorted(set(a for n, a in labels.items() if 0x8000 <= a < 0x10000))
    out = {}
    for proc in PAIRS:
        a = labels[proc]
        nxt = next(x for x in starts if x > a)
        # the next label may be one of the proc's own locals: use the next proc
        procs_after = sorted(v for k, v in labels.items() if v > a and k in ALL_PROCS)
        end = procs_after[0] if procs_after else nxt
        out[proc] = [f"{x:02X}" for x in rom[a - 0x8000:end - 0x8000]]
    return out


def calypsi_bytes(lst):
    labels, cur = {}, None
    for line in open(lst, encoding="latin-1"):
        m2 = re.match(r"^\d{4}\s+(?:[0-9a-f]{6}\s+(?:[0-9a-f.]+\s+)?)?(\w+):", line)
        if m2 and m2.group(1) in PAIRS.values():
            cur = labels.setdefault(m2.group(1), [])
        mm = re.match(r"^(?:\d{4}|\s+\\)\s+[0-9a-f]{6}\s+([0-9a-f.]{2,})\s+(?:[\w$]+:\s*)?([a-z]{3})\b", line)
        if cur is not None and mm:
            h = mm.group(1)
            cur += ["??" if h[i:i + 2] == ".." else h[i:i + 2].upper() for i in range(0, len(h), 2)]
    return labels


# deliberate substitution: "pea $0000 / pld" became "lda ##0 / tcd"
def norm(b):
    s = " ".join(b).replace("F4 00 00 2B", "A9 00 00 5B")
    return s.split()


_legacy_src = open("legacy/main.s").read()
# routines end at the next proc or the next top-level (data) label
ALL_PROCS = set(re.findall(r"^\.proc (\w+)", _legacy_src, re.M)) | \
    set(re.findall(r"^([A-Za-z_]\w*):", re.sub(r"\.proc.*?\.endproc", "", _legacy_src, flags=re.S), re.M))
old = legacy_bytes("build/legacy/nolfied.sfc", "build/legacy/nolfied.lbl")

# field_fill_k is legacy do_fill's flood/claim/edge half: the same bytes,
# minus the boss lookup "ldx #0 / jsr enemy_cell" (6 bytes after
# "stz noseed"; the seed now arrives in Y), ending where legacy goes on to
# compute the percentage (the kernel returns there instead).
def _legacy_do_fill():
    rom = open("build/legacy/nolfied.sfc", "rb").read()
    lab = {}
    for line in open("build/legacy/nolfied.lbl"):
        _, adr, name = line.split()
        lab[name[1:]] = int(adr, 16)
    a = lab["do_fill"]
    b = bytes(rom[a - 0x8000:a - 0x8000 + 400])
    body = b[:2] + b[8:]
    return [f"{x:02X}" for x in body]


PAIRS["do_fill"] = "field_fill_k"
_ff = new_bytes = None
new = calypsi_bytes("build/core.lst")
if "field_fill_k" in new:
    # the kernel must equal legacy up to the point where legacy goes on with
    # "rep #$20" (the percentage code) and the kernel returns ("rts") instead
    k, legacy = new["field_fill_k"], _legacy_do_fill()
    d = next(i for i in range(len(k)) if k[i] != legacy[i] and "??" not in (k[i], legacy[i]))
    if k[d] == "60" and legacy[d:d + 2] == ["C2", "20"]:
        new["field_fill_k"], old["do_fill"] = k[:d], legacy[:d]
    else:
        new["field_fill_k"], old["do_fill"] = k[:d + 1], legacy[:d + 1]
bad = 0
for lp, np_ in PAIRS.items():
    a, b = norm(old.get(lp, [])), new.get(np_, [])[:len(old.get(lp, []))]
    diff = next((i for i in range(len(a)) if i >= len(b) or not (a[i] == b[i] or "??" in (a[i], b[i]))), None)
    bad += diff is not None
    where = "" if diff is None else f"  first difference at byte {diff}: ca65 {a[max(0,diff-3):diff+3]} vs calypsi {b[max(0,diff-3):diff+3]}"
    print(f"{'ok  ' if diff is None else 'DIFF'} {lp:16s} {len(a):5d} bytes{where}")
sys.exit(1 if bad else 0)
