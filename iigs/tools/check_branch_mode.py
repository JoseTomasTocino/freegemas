#!/usr/bin/env python3
"""Audit Merlin32 accumulator-width hazards at branch targets in main.s.

Merlin32 decides the size of "LDA #$xx" style immediates from the *linear*
SEP/REP flow it has seen so far.  A label that is reached by a branch taken
from the other width therefore assembles correctly for the linear path but
executes one byte short: the leftover operand byte ($00 in the common case)
runs as BRK and drops the game into GSBug.  This bit us three times already
(vsyncPoll, overKeyDown, mpFull/mousePoll).

The checker reports every branch whose width differs from the width the
assembler assumed at the target label, unless the label starts with an
explicit SEP/REP that re-syncs the mode before any immediate is used.

Usage (from the repository root or anywhere):
    python iigs/tools/check_branch_mode.py [path/to/main.s]

Exit code 0 = clean, 1 = findings.
"""

import re
import sys
from dataclasses import dataclass, field

DATA_DIRECTIVES = {
    "dw", "db", "ds", "adrl", "adrl", "put", "end", "org", "use", "dsk", "typ",
    "rel", "mx", "xc", "knd", "sna", "lna", "ali", "ent", "ext", "seg", "equ",
    "as",
}

# Mnemonics that end the linear flow (no fall-through).
FLOW_TERMINATORS = {"rts", "rtl", "brk", "cop", "jmp", "jml", "bra", "brl", "per"}
# Conditional branches with a label operand.
CONDITIONAL = {
    "bpl", "bmi", "bvc", "bvs", "bcc", "bcs", "bne", "beq",
}
UNCONDITIONAL_BRANCH = {"bra", "brl", "jmp", "jml"}

LABEL_RE = re.compile(r"^([A-Za-z_.@][^\s;*]*)")
BRANCH_RE = re.compile(r"^(bpl|bmi|bvc|bvs|bcc|bcs|bne|beq|bra|brl|per)\s+([A-Za-z_.@][^\s,;]*)", re.I)
JMP_RE = re.compile(r"^(jmp|jml)\s+([A-Za-z_.@][^\s,;]*)", re.I)
SEP_REP_RE = re.compile(r"^(sep|rep)\s+#\$([0-9A-Fa-f]{2})", re.I)


@dataclass
class Instr:
    line: int
    label: str | None
    mnemonic: str
    operand: str
    mode_before: int | None = None  # 8 or 16 (accumulator width)
    mode_after: int | None = None


def strip_comment(text: str) -> str:
    """Remove a trailing ';' comment (Merlin treats '*' at column 1 as a comment)."""
    if text.startswith("*"):
        return ""
    out = []
    for ch in text:
        if ch == ";":
            break
        out.append(ch)
    return "".join(out)


def parse(path: str) -> list[Instr]:
    instrs: list[Instr] = []
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for lineno, raw in enumerate(fh, 1):
            text = strip_comment(raw.rstrip("\r\n"))
            if not text.strip():
                continue
            label = None
            rest = text
            m = LABEL_RE.match(text)
            if m and not text[0].isspace():
                label = m.group(1)
                rest = text[len(label):]
            else:
                rest = text.lstrip()
            if not rest.strip():
                instrs.append(Instr(lineno, label, "", "", None, None))
                continue
            parts = rest.split(None, 1)
            mnemonic = parts[0].lower()
            operand = parts[1] if len(parts) > 1 else ""
            instrs.append(Instr(lineno, label, mnemonic, operand, None, None))
    return instrs


def linear_modes(instrs: list[Instr]) -> None:
    mode = 16  # the segment prologue does REP #$30 before any immediate
    for ins in instrs:
        ins.mode_before = mode
        if not ins.mnemonic:
            ins.mode_after = mode
            continue
        mm = SEP_REP_RE.match(f"{ins.mnemonic} {ins.operand}")
        if mm:
            bits = int(mm.group(2), 16)
            if mm.group(1).lower() == "sep" and bits & 0x20:
                mode = 8
            elif mm.group(1).lower() == "rep" and bits & 0x20:
                mode = 16
        ins.mode_after = mode


# Mnemonics that do not care about the accumulator width: we may walk through
# them while looking for the first width-dependent instruction at a label.
WIDTH_AGNOSTIC = {
    "nop", "anop", "jsr", "jsl", "rts", "rtl", "pha", "php", "phx", "phy",
    "plx", "ply", "plp", "pla", "phb", "phd", "phk", "pld", "plb", "xce",
    "clc", "sec", "cld", "sed", "clv", "sei", "cli", "tax", "tay", "txa",
    "tya", "tsx", "txs", "txy", "tyx", "inx", "iny", "dex", "dey", "inc",
    "dec", "asl", "lsr", "rol", "ror", "sta", "stx", "sty", "stz", "ldx",
    "ldy", "lda", "cmp", "bra", "brl", "jmp", "jml", "stp", "wai", "pea",
    "pei", "per", "mvn", "mvp", "ldx_st", "tcs", "tsc",
}

# Instructions whose immediate operand width follows the accumulator width.
ACC_IMMEDIATE = {"lda", "and", "ora", "eor", "adc", "sbc", "cmp", "bit"}


def scan_target(instrs: list[Instr], index: int) -> tuple[str, Instr | None, int | None]:
    """Walk forward from a label to the first width-relevant instruction.

    Returns (verdict, instruction, mode) where verdict is one of
    'self' (SEP/REP with the A bit re-syncs the width), 'immediate'
    (mode-dependent immediate: compare modes), 'unknown' (hit a transfer or a
    data directive first; nothing to check here).
    """
    for j in range(index, len(instrs)):
        ins = instrs[j]
        if not ins.mnemonic:
            continue
        mnemonic = ins.mnemonic.lower()
        if mnemonic in DATA_DIRECTIVES:
            return "unknown", ins, None
        mm = SEP_REP_RE.match(f"{ins.mnemonic} {ins.operand}")
        if mm:
            bits = int(mm.group(2), 16)
            if bits & 0x20:
                return "self", ins, None
            continue
        if mnemonic in ACC_IMMEDIATE:
            if ins.operand.strip().startswith("#"):
                return "immediate", ins, ins.mode_before
            continue
        if mnemonic in WIDTH_AGNOSTIC:
            continue
        return "unknown", ins, None
    return "unknown", None, None


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "iigs/merlin32/src/main.s"
    instrs = parse(path)
    linear_modes(instrs)

    label_index: dict[str, int] = {}
    for i, ins in enumerate(instrs):
        if ins.label is not None:
            label_index.setdefault(ins.label.upper(), i)

    findings: list[str] = []
    self_correcting = 0
    for i, ins in enumerate(instrs):
        if not ins.mnemonic:
            continue
        m = BRANCH_RE.match(f"{ins.mnemonic} {ins.operand}")
        if not m:
            continue
        target = m.group(2).strip()
        if target.upper() not in label_index:
            continue  # computed / indirect / local +- form
        j = label_index[target.upper()]
        # Width the branch runs with: the linear width at the branch itself.
        src_mode = ins.mode_before
        verdict, first, tgt_mode = scan_target(instrs, j)
        if verdict == "self":
            # The target re-syncs the mode explicitly before any immediate,
            # so the linear/run-time width may differ safely.
            self_correcting += 1
            continue
        if verdict != "immediate" or first is None or tgt_mode is None:
            continue
        if src_mode is not None and src_mode != tgt_mode:
            findings.append(
                f"{path}:{ins.line}: {ins.mnemonic} {target} taken with A={src_mode}-bit "
                f"but the assembler assumed A={tgt_mode}-bit at '{target}' "
                f"(line {instrs[j].line}); first width-dependent immediate is "
                f"'{first.mnemonic} {first.operand.strip()}' at line {first.line}"
            )

    for f in findings:
        print(f)
    print(
        f"checked {len(instrs)} lines, {len(label_index)} labels; "
        f"{len(findings)} suspect branch target(s), "
        f"{self_correcting} self-correcting (SEP/REP at the label)"
    )
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
