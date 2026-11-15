#!/usr/bin/env python3
"""Turn ln65816's cross-reference list into a VICE-style label file
("al ADDR .name", the format ld65 -Ln wrote) so the test tools keep looking
symbols up by name: python3 tools/calypsi_lbl.py build/nolfied.lst out.lbl"""
import re
import sys

text = open(sys.argv[1]).read()
syms = {}
for name, addr in re.findall(r"^\s+([A-Za-z_]\w*) = ([0-9A-Fa-f]+)$", text, re.M):
    syms[name] = int(addr, 16)
# section bounds the tests need (e.g. the C stack, for overflow checks)
for sec in ("stack",):
    m = re.search(rf"^{sec}\s+.*?placed at address ([0-9A-Fa-f]+)-([0-9A-Fa-f]+)", text, re.M) or \
        re.search(rf"[Ss]ection '{sec}'\s+placed at address ([0-9A-Fa-f]+)-([0-9A-Fa-f]+)", text, re.M)
    if m:
        syms[f"__{sec}_start"] = int(m.group(1), 16)
        syms[f"__{sec}_end"] = int(m.group(2), 16)
with open(sys.argv[2], "w") as f:
    for name, addr in sorted(syms.items(), key=lambda kv: kv[1]):
        f.write(f"al {addr:06X} .{name}\n")
print(f"{sys.argv[2]}: {len(syms)} symbols")
