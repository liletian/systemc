#!/usr/bin/env python3
"""Summarise a RiSC.v simulation log as a list of events.

Reads the per-cycle $display blocks that RiSC.v prints and reports, per cycle:
  - an exception or system call reaching write-back (code, faulting PC, next PC)
  - each TLB write (asid:vpn -> pfn)
  - the halt
plus the user registers at the end.

usage: timeline.py LOG
"""
import re
import sys

EXC = {
    "02": "sys MODE_HALT",
    "30": "rfe",
    "51": "user TLB miss",
    "52": "kernel TLB miss",
    "71": "trap HALT (system call)",
}

def cycles(path):
    block = None
    with open(path, errors="replace") as f:
        for line in f:
            line = line.rstrip("\r\n")
            m = re.match(r"-+ \(time ([0-9a-fx]+)\)", line)
            if m:
                if block:
                    yield block
                block = {"time": int(m.group(1), 16) if "x" not in m.group(1) else None}
                continue
            if block is None:
                continue
            for key, pat in (
                ("regs", r"regs\s+(.*)"),
                ("ctl", r"ctl:\s+(.*)"),
                ("pc", r"-Fetch\s+PC=(\w+)"),
                ("wb", r"-Write .*MEMWB_pc=(\w+) MEMWB_exc=(\w+)"),
                ("tlbw", r" tlb2\s+asid=(\w+) vpn=(\w+) .*map=(\w+) tlb_we=(\w)"),
            ):
                m = re.match(pat, line)
                if m:
                    block[key] = m.groups() if len(m.groups()) > 1 else m.group(1)
    if block:
        yield block

def main(path):
    blocks = [b for b in cycles(path) if b.get("time") is not None]
    if not blocks:
        print("no cycles found")
        return 1
    print(f"{'cycle':>5}  {'time':>6}  event")
    for i, b in enumerate(blocks):
        nxt = blocks[i + 1]["pc"] if i + 1 < len(blocks) else "----"
        pc, exc = b.get("wb", ("", "00"))
        if exc not in ("00", "xx"):
            name = EXC.get(exc, "exception")
            if exc == "02":
                print(f"{i:5}  {b['time']:6}  halt: {name} from pc {pc}")
            elif exc == "30":
                print(f"{i:5}  {b['time']:6}  rfe        -> resume at {nxt}")
            else:
                print(f"{i:5}  {b['time']:6}  exc 0x{exc} {name:<24} pc {pc} -> vector {nxt}")
        tw = b.get("tlbw")
        if tw and tw[3] == "1":
            print(f"{i:5}  {b['time']:6}  tlbw       asid {int(tw[0],16)}: vpn {tw[1]} -> pfn {tw[2]}")
    last = blocks[-1]
    print(f"\n{len(blocks)} cycles; final user regs r1-r7: {last.get('regs','?')}")
    print(f"final control regs cr1-cr3, PSR, cr5-cr7:    {last.get('ctl','?')}")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
