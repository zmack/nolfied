#!/usr/bin/env python3
"""One-shot translator from the legacy ca65 source to Calypsi as65816 syntax.

Used to carry the hardware/kernel routines of legacy/main.s over to
src/core.s. It mirrors what ca65's `.smart` mode did: it tracks the
accumulator width through A8/A16/sep/rep linearly from each `.proc` (which
starts in 8-bit A, 16-bit X/Y), and emits `#` (8-bit) or `##` (16-bit)
immediates accordingly, because as65816 does not track modes itself.

    python3 tools/ca65_to_calypsi.py legacy/main.s proc1 proc2 ... > out.s

The output is verified opcode-for-opcode against ca65's own listing by
tools/verify_port.py, so a width mistake here cannot slip through.
"""
import re
import sys

A_OPS = {"lda", "adc", "sbc", "cmp", "and", "ora", "eor", "bit"}
X_OPS = {"ldx", "ldy", "cpx", "cpy"}


def expr(e):
    e = re.sub(r"\$([0-9A-Fa-f]+)", r"0x\1", e)
    e = re.sub(r"%([01]+)", r"0b\1", e)
    e = re.sub(r"\.loword\(([^)]*)\)", r".word0 (\1)", e)
    e = re.sub(r"\^(\w+)", r".byte2 \1", e)
    e = re.sub(r"<\(([^)]*)\)", r".byte0 (\1)", e)
    e = re.sub(r">\(([^)]*)\)", r".byte1 (\1)", e)
    e = re.sub(r"\bf:", "long:", e)
    e = re.sub(r"\ba:", "abs:", e)
    return e


def split_procs(src):
    procs, cur, name = {}, None, None
    for line in src.split("\n"):
        m = re.match(r"^\.proc (\w+)", line)
        if m:
            name, cur = m.group(1), []
            continue
        if line.startswith(".endproc"):
            procs[name] = cur
            name, cur = None, None
            continue
        if cur is not None:
            cur.append(line)
    return procs


def convert(name, lines):
    out = [f"{name}:"]
    width = 8
    anon = []          # anonymous label numbers in this proc, in order
    # pass 1: number anonymous labels
    n = 0
    marks = []
    for line in lines:
        code = line.split(";")[0]
        if re.match(r"^:\s", code) or code.strip() == ":":
            marks.append(n)
            n += 1
        else:
            marks.append(None)
    seen = 0
    for idx, line in enumerate(lines):
        code, _, comment = line.partition(";")
        comment = (" ;" + comment) if comment else ""
        label = ""
        if marks[idx] is not None:
            label = f"{name}_a{marks[idx]}:"
            code = code.split(":", 1)[1]
            seen = marks[idx] + 1
        m = re.match(r"^@(\w+):(.*)$", code)
        if m:
            label = f"{name}_{m.group(1)}:"
            code = m.group(2)
        m = re.match(r"^(\w+):(.*)$", code)
        if m and not label:
            label = f"{m.group(1)}:"
            code = m.group(2)
        code = code.strip()
        if code in (".a8", ".i16", ".a16", ".i8"):
            if code == ".a16":
                width = 16
            elif code == ".a8":
                width = 8
            code = ""
        if code == "A8":
            code, width = "sep #0x20", 8
        elif code == "A16":
            code, width = "rep #0x20", 16
        parts = code.split(None, 1)
        op = parts[0].lower() if parts else ""
        arg = parts[1].strip() if len(parts) > 1 else ""
        # local and anonymous references
        arg = re.sub(r"@(\w+)", lambda mm: f"{name}_{mm.group(1)}", arg)

        def anon_ref(mm):
            ref = mm.group(1)                  # ":+", ":++", ":-", ...
            k = len(ref) - 1
            target = seen - 1 + k if ref[1] == "+" else seen - k
            return f"{name}_a{target}"
        arg = re.sub(r"(?<![\w:])(:\++|:-+)", anon_ref, arg)
        if op in ("rep", "sep"):
            v = int(arg.lstrip("#").replace("$", "0x"), 0)
            if v & 0x20:
                width = 16 if op == "rep" else 8
            arg = f"#0x{v:02x}"
        elif arg.startswith("#"):
            hashes = "##" if (op in X_OPS or (op in A_OPS and width == 16)) else "#"
            arg = hashes + expr(arg[1:])
        else:
            arg = expr(arg)
        if op == ".res":
            op = ".space"
        if op in ("asl", "lsr", "rol", "ror", "inc", "dec") and arg in ("", "a", "A"):
            arg = "a"                          # as65816 wants the accumulator spelled out
        if op == "pea" and arg in ("$0000", "0x0000", "0"):
            op, arg = "lda", "##0"             # direct page := 0 (A is saved by now)
        if op == "pld" and out and out[-1].strip().startswith("lda     ##0"):
            op = "tcd"
        text = (f"{op:7s} {arg}".rstrip()) if op else ""
        if label and text:
            out.append(f"{label:14s}{text}{comment}")
        elif label:
            out.append(f"{label}{comment}")
        elif text or comment:
            out.append(f"              {text}{comment}".rstrip())
    return out


def main():
    src = open(sys.argv[1]).read()
    procs = split_procs(src)
    for name in sys.argv[2:]:
        print("\n".join(convert(name, procs[name])))
        print()


if __name__ == "__main__":
    main()
