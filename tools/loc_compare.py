#!/usr/bin/env python3
"""Size and legibility numbers: the C game (src/) vs the legacy assembly.

Counts code lines (no blanks, no comment-only lines), functions, average
function length, and accumulator-width switches (A8/A16/sep/rep lines: pure
bookkeeping a reader has to track in assembly, and none in the C).
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def c_stats(path):
    text = re.sub(r"/\*.*?\*/", "", open(path).read(), flags=re.S)
    lines = [l for l in text.split("\n") if l.strip() and not l.strip().startswith("//")]
    funcs = re.findall(r"^[A-Za-z_][\w\s\*]*\b(\w+)\s*\([^;{]*\)\s*\{", text, re.M)
    return len(lines), len(funcs)


def asm_stats(text):
    lines = [l for l in text.split("\n") if l.strip() and not l.strip().startswith(";")]
    data = [l for l in lines if re.match(r"\s*(\w+:)?\s*\.(byte|word|res|space|asciiz|ascii|incbin|addr)", l)]
    width = [l for l in lines if re.match(r"\s*(\w+:)?\s*(A8|A16|sep|rep)\b", l)]
    return len(lines) - len(data), len(width)


legacy = open(os.path.join(ROOT, "legacy", "main.s")).read()
legacy = re.sub(r"\.ifdef (BENCH|PERF).*?\.endif", "", legacy, flags=re.S)
l_lines, l_width = asm_stats(legacy)
l_funcs = len(re.findall(r"^\.proc ", legacy, re.M))

core = open(os.path.join(ROOT, "src", "core.s")).read()
k_lines, k_width = asm_stats(core)
# routines: everything called with jsr/jmp from another label, plus the
# entry points C calls (".public" names that are code labels)
called = set(re.findall(r"\bj(?:sr|mp)\s+(\w+)", core))
public = set(n.strip() for l in re.findall(r"\.public\s+(.*)", core) for n in l.split(","))
labels_ = set(re.findall(r"^([A-Za-z_]\w*):", core, re.M))
k_funcs = len((called | public) & labels_ - {n for n in labels_ if re.search(r"_(a\d+|k_\w+)$", n)})

c_total, c_funcs, rows = 0, 0, []
for f in sorted(os.listdir(os.path.join(ROOT, "src"))):
    if f.endswith((".c", ".h")):
        n, k = c_stats(os.path.join(ROOT, "src", f))
        c_total += n
        c_funcs += k if f.endswith(".c") else 0
        rows.append((f, n, k))

print(f"{'':28s}{'code lines':>11s}{'functions':>11s}{'lines/fn':>10s}{'width switches':>16s}")
print(f"{'legacy/main.s (all asm)':28s}{l_lines:11d}{l_funcs:11d}{l_lines / l_funcs:10.1f}{l_width:16d}")
print(f"{'src/*.c + *.h (game logic)':28s}{c_total:11d}{c_funcs:11d}{c_total / max(c_funcs, 1):10.1f}{0:16d}")
print(f"{'src/core.s (asm core)':28s}{k_lines:11d}{k_funcs:11d}{k_lines / k_funcs:10.1f}{k_width:16d}")
print("\nper C file:")
for f, n, k in rows:
    print(f"  {f:14s} {n:5d} lines" + (f"  {k:3d} functions" if f.endswith('.c') else ""))
