#!/bin/sh
# extra: boot from ROM with the step-4 design (RiSC.v compiled with -DBOOT)
cd "$(dirname "$0")" && . ../../tools/lib.sh
DESIGN=../../step4_tlb_umiss/design
setup "EXTRA  boot ROM: reset to 0x7e00 in kernel mode, load the OS from the simulated disk"
run_tb boot test-BOOT.v -DBOOT init.rom:rom-BOOT init.sys:sys-iii-iv init.usr1:usr-iii
python3 -I "$ROOT/tools/timeline.py" logs/boot.log > logs/boot.timeline.txt
if grep -q 'reading init.sys into 0000' logs/boot.log \
	&& grep -- '^-Fetch' logs/boot.log | awk '/PC=7e1e/{f=1;next} f{print;exit}' | grep -q 'PC=0000'; then
	say "boot: boot ROM ran, loaded the OS from disk, entered user code at 0x0000"
else say "boot: boot ROM did NOT complete"; status=1; fi
grep -- '^-Fetch' "$ROOT/reference/BOOT-log.txt" | awk '{print $2}' > "$ROOT/build/b1"
grep -- '^-Fetch' logs/boot.log | awk '{print $2}' > "$ROOT/build/b2"
n=$(cmp "$ROOT/build/b1" "$ROOT/build/b2" 2>&1 | grep -o 'line [0-9]*' | awk '{print $2-1}')
say "      first $n fetches identical to reference/BOOT-log.txt (that kernel's handlers sit at other addresses)"
say "      not expected to halt: the kernel has no page-fault handler, so the user program is never loaded"
finish
