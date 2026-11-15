#!/usr/bin/env python3
"""Find accumulator-width mismatches in Calypsi's generated 65816 code.

Calypsi 5.18 sometimes emits a basic block written for 8-bit accumulator
mode at a branch target that is also reached in 16-bit mode (e.g. a loop
body starting with `asl var` reached from a `rep #32; bne ...`). The 16-bit
read-modify-write then also clobbers the neighbouring byte. See
experiments/c-trial/README.md.

This tool rebuilds each function's control flow from a compiler listing
(cc65816 -l), propagates the possible M-flag states along every path
(16-bit at function entry and after every call, as the calling convention
guarantees), and reports every width-dependent instruction that can be
reached in BOTH widths. That ambiguity is exactly the miscompile: the
compiler chose one width for the instruction, and some path disagrees.

    python3 tools/check_modes.py build/*.lst      (exit 1 if anything found)
"""
import re
import sys

# instructions whose behaviour depends on the accumulator width (M flag)
A_DEP = {"lda", "sta", "stz", "adc", "sbc", "and", "ora", "eor", "cmp", "bit",
         "inc", "dec", "asl", "lsr", "rol", "ror", "tsb", "trb", "pha", "pla",
         "txa", "tya"}
BRANCH = {"bcc", "bcs", "beq", "bne", "bmi", "bpl", "bvc", "bvs"}
LINE = re.compile(r"^(?:\s*\\)?\s*[0-9a-f]{6}\s+[0-9a-f.]{2,}\s+(?:(`[^`]+`|[A-Za-z_][\w$]*):\s*)?([a-z]{3})\b\s*(.*)$")
LABEL_ONLY = re.compile(r"^(?:\s*\\)?\s*[0-9a-f]{6}\s+(`[^`]+`|[A-Za-z_][\w$]*):\s*$")
SECTION = re.compile(r"^(?:\s*\\)?\s*[0-9a-f]{6}\s+\.section\s+(\w+)")



def last_store_16(func, states, i, slot):
    """True if, in the straight-line code before instruction i, the slot was
    last written by a 16-bit store: then it holds a 16-bit value (Calypsi
    reuses stack slots for variables of different sizes) and a 16-bit
    read-modify-write on it is correct."""
    for j in range(i - 1, -1, -1):
        labels, op, arg, src = func[j]
        if op == "sta" and arg == f"{slot},s":
            return states[j] == {16}
        if labels or op in ("jsr", "jsl", "rts", "rtl", "bra", "brl", "jmp"):
            return False
    return False

def parse(path):
    """-> list of functions, each a list of (label_or_None, op, arg, srcline)"""
    funcs, cur, pending, in_code = [], None, [], False
    for raw in open(path, encoding="latin-1"):
        line = raw.rstrip("\n")
        s = SECTION.match(line)
        if s:
            in_code = s.group(1) in ("code", "farcode", "compactcode")
            continue
        if not in_code:
            continue
        m = LABEL_ONLY.match(line)
        if m:
            pending.append(m.group(1))
            continue
        m = LINE.match(line)
        if not m:
            continue
        lab, op, arg = m.groups()
        labels = pending + ([lab] if lab else [])
        pending = []
        if any(not l.startswith("`") for l in labels):   # a named label: new function
            cur = []
            funcs.append(cur)
        if cur is None:
            cur = []
            funcs.append(cur)
        cur.append((labels, op, arg.split(";")[0].strip(), line.strip()))
    return funcs


FRAGMENTS = {}          # `?Lnn` cross-call fragments of the current listing


def fragment_exit(label, mode, depth=0):
    """width after `jsr label` to a compiler cross-call fragment"""
    body = FRAGMENTS.get(label)
    if body is None or depth > 8:
        return 16                      # a real function: returns in 16-bit
    for op, arg in body:
        if op == "rep" and re.search(r"#\s*(32|0x20|0x30|48)", arg):
            mode = 16
        elif op == "sep" and re.search(r"#\s*(32|0x20|0x30|48)", arg):
            mode = 8
        elif op in ("jsr", "jsl"):
            mode = fragment_exit(arg.strip(), mode, depth + 1)
        elif op in ("rts", "rtl"):
            return mode
    return mode


def analyse(func):
    index = {}
    for i, (labels, *_rest) in enumerate(func):
        for l in labels:
            index[l] = i
    states = [set() for _ in func]
    states[0].add(16)
    work = [0]
    while work:
        i = work.pop()
        for m in list(states[i]):
            j, mode = i, m
            while j < len(func):
                if mode not in states[j] and j != i:
                    states[j].add(mode)
                elif j != i and mode in states[j]:
                    break
                labels, op, arg, _ = func[j]
                if op == "rep" and re.search(r"#\s*(32|0x20|0x30|48)", arg):
                    mode = 16
                elif op == "sep" and re.search(r"#\s*(32|0x20|0x30|48)", arg):
                    mode = 8
                elif op in ("jsr", "jsl"):
                    mode = fragment_exit(arg.strip(), mode)  # functions return 16-bit
                elif op in ("plp",):
                    mode = mode                   # assume php/plp pairs restore
                target = arg.split(",")[0].strip()
                if op in BRANCH or op in ("bra", "brl", "jmp"):
                    if target in index:
                        k = index[target]
                        if mode not in states[k]:
                            states[k].add(mode)
                            work.append(k)
                    if op in ("bra", "brl", "jmp"):
                        break
                if op in ("rts", "rtl", "rti"):
                    break
                j += 1
    # stack slots this function touches with 8-bit accesses ("n,s" in M=8)
    byte_slots = set()
    for i, (labels, op, arg, src) in enumerate(func):
        m = re.match(r"^(\d+),s$", arg)
        if m and op in A_DEP and 8 in states[i]:
            byte_slots.add(int(m.group(1)))
    problems = []
    # rule 1: an instruction reachable in both widths. Its encoding (immediate
    # size) and effect were chosen for one width; the other path desyncs.
    for i, (labels, op, arg, src) in enumerate(func):
        if op in A_DEP and len(states[i]) > 1:
            problems.append(f"reachable in 8- and 16-bit mode: {src}")
    # rule 2: 16-bit writes to byte-sized objects (they clobber the next byte)
    xoff = None                       # X = S + xoff after "tsc; inc a...; tax"
    for i, (labels, op, arg, src) in enumerate(func):
        if labels:
            xoff = None if xoff is None else xoff
        if op == "tsc":
            xoff = 0
        elif op == "inc" and arg == "a" and xoff is not None:
            xoff += 1
        elif op == "tax" and xoff is not None:
            pass
        elif op not in ("tax",) and op not in ("inc",) and xoff is not None and op not in RMW and op != "sep":
            xoff = None if op not in ("sep", "rep") else xoff
        if 16 not in states[i] or op not in RMW | {"sta", "stz"}:
            continue
        target = arg.split(",")[0].strip()
        if target in sizes and sizes[target] == 1 and "," not in arg:
            problems.append(f"16-bit {op} on 1-byte '{target}': {src}")
        m = re.match(r"^(\d+),s$", arg)
        if m and int(m.group(1)) in byte_slots and op in RMW \
                and not last_store_16(func, states, i, int(m.group(1))):
            problems.append(f"16-bit {op} on byte stack slot {m.group(1)},s: {src}")
        if arg in ("0,x",) and xoff is not None and xoff in byte_slots and op in RMW \
                and not last_store_16(func, states, i, xoff):
            problems.append(f"16-bit {op} on byte stack slot {xoff},s (via X): {src}")
    return problems


RMW = {"inc", "dec", "asl", "lsr", "rol", "ror", "tsb", "trb"}
sizes = {}


def load_sizes(map_path):
    """object sizes from the linker cross reference ("x in section ... of size n")"""
    try:
        text = open(map_path).read()
    except OSError:
        return
    for name, size in re.findall(r"^(\S+) in section '\w+'\s+placed at address \S+ of size ([0-9a-fA-F]+)", text, re.M):
        sizes[name.strip("`")] = int(size, 16)


def main(paths):
    found = 0
    maps = [p for p in paths if p.endswith("nolfied.lst")]
    for m in maps or ["build/nolfied.lst"]:
        load_sizes(m)
    paths = [p for p in paths if not p.endswith("nolfied.lst") and not p.endswith("core.lst")]
    for path in paths:
        funcs = parse(path)
        FRAGMENTS.clear()
        for func in funcs:
            for i, (labels, op, arg, src) in enumerate(func):
                for l in labels:
                    if l.startswith("`"):
                        body = []
                        for _labels, o, a, _s in func[i:]:
                            body.append((o, a))
                            if o in ("rts", "rtl", "jmp", "bra"):
                                break
                        FRAGMENTS[l] = body
        for func in funcs:
            probs = analyse(func)
            if probs:
                name = next((l for l in func[0][0] if not l.startswith("`")), "?")
                found += len(probs)
                print(f"{path}: {name}:")
                for p in probs[:6]:
                    print("    " + p)
    if found:
        print(f"\n{found} accumulator-width miscompile(s)")
    else:
        print(f"no accumulator-width miscompiles in {len(paths)} listing(s)")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
