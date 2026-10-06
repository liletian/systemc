#!/bin/sh
# Assemble the course sources and run every stage with the course testbenches
# against ../RiSC.v and ../memories.v. Needs gcc, iverilog and vvp.
#
#   stage  testbench     kernel (init.sys)  user program (init.usr)
#   i      test-i.v      sys-i.s            usr-i.s        loaded at 0, no translation
#   ii     test-ii.v     sys-ii.s           usr-ii.s       loaded at 0x300, TLB-A preloaded
#   iii    test-iii.v    sys-iii-iv.s       usr-iii.s      kernel page 0xc9 preloaded in TLB-B
#   iv     test-iv.v     sys-iii-iv.s       usr-iii.s, usr-iv-dmiss.s, usr-iv-imiss.s (empty TLB)
#   boot   test-BOOT.v   sys-iii-iv.s       usr-iii.s as init.usr1, rom-BOOT.s as init.rom (+define+BOOT)
cd "$(dirname "$0")"
mkdir -p out && cd out
gcc -std=gnu89 -w -include stdlib.h -include ctype.h -o asm ../a.c || exit 1
asm() { ./asm ../$1 $2 > /dev/null || { echo "assembler failed on $1"; exit 1; }; }
filt() { tr -d '\r' < "$1" | grep -E '^(-------------|regs |ctl: |-Fetch| tlb1| mem1|-Decode|-Exec| ALU|-Memory| tlb2| mem2|-Write|etc\. |MUXpc|TLB-[AB])' | sed 's/(time 0*\([0-9a-f]\)/(time \1/'; }
status=0

# run <stage> <testbench> <kernel.s> <user.s> [reference log] [expected regs]
run() {
	asm $3 init.sys; asm $4 init.usr
	iverilog -g2005 -o sim ../$2 ../../RiSC.v ../../memories.v 2>/dev/null || { echo "$1: compile failed"; exit 1; }
	vvp -n sim > $1.log
	cyc=$(grep -c '^-Fetch' $1.log)
	regs=$(grep -B20 'MEMWB_exc=02' $1.log | grep '^regs' | tail -1 | cut -c9-)
	if [ -z "$regs" ]; then echo "$1 ($4): FAIL, did not halt"; status=1; return; fi
	msg="$1 ($4): halts after $cyc cycles, user regs $regs"
	if [ -n "$5" ]; then
		f=cat; [ $1 = i ] && f="grep -v -E ^(.tlb[12].|TLB-)"	# phase-1 reference used a stub TLB
		filt ../../$5 | $f > ref.f; filt $1.log | $f > out.f
		if diff -q ref.f out.f > /dev/null; then msg="$msg, every cycle matches $5"; else msg="$msg, DIFFERS from $5"; status=1; fi
	fi
	if [ -n "$6" ] && [ "$regs" != "$6" ]; then msg="$msg, WRONG (want $6)"; status=1; fi
	echo "$msg"
}

run i    test-i.v   sys-i.s      usr-i.s        ref-phase1.log
run ii   test-ii.v  sys-ii.s     usr-ii.s       ref-phase2.log
run iii  test-iii.v sys-iii-iv.s usr-iii.s      ref-phase3.log
run iv   test-iv.v  sys-iii-iv.s usr-iii.s      "" "2112 0000 0000 0000 0000 0000 0f00"
run iv-d test-iv.v  sys-iii-iv.s usr-iv-dmiss.s "" "0001 0002 0003 0004 0c00 0b00 0a00"
run iv-i test-iv.v  sys-iii-iv.s usr-iv-imiss.s "" "0001 0002 0003 0004 000a 000b 000c"

# boot: the ROM must load the OS from disk and rfe to user code; finishing needs a page-fault handler
asm rom-BOOT.s init.rom; asm sys-iii-iv.s init.sys; asm usr-iii.s init.usr1
iverilog -g2005 -DBOOT -o sim ../test-BOOT.v ../../RiSC.v ../../memories.v 2>/dev/null || exit 1
vvp -n sim > boot.log
if grep -q 'reading init.sys into 0000' boot.log && grep -A1 'PC=7e1e' boot.log | grep -q . && grep -- '-Fetch' boot.log | awk '/7e1e/{f=1;next} f{print;exit}' | grep -q 'PC=0000'; then
	echo "boot: boot ROM ran, OS loaded from disk, rfe to user code at 0x0000 (no page-fault handler yet, so the user program is never loaded)"
else echo "boot: FAIL, boot ROM did not complete"; status=1; fi
exit $status
