#!/bin/sh
# Rebuild and run every stage of the RiSC-16 project.
#
#   1. build the assembler (assembler/a.c)
#   2. assemble every program in software/ into images/*.hex and check the
#      course-provided images in reference/provided-images/ are reproduced
#   3. run each stage's course testbench against design/RiSC.v
#   4. write logs/<stage>.log (full simulator output), logs/<stage>.timeline.txt
#      (exceptions, TLB writes, halt) and logs/summary.txt
#
# Needs: gcc, iverilog/vvp (Icarus Verilog 12), python3.  Exit status 0 = all pass.
cd "$(dirname "$0")"
mkdir -p build images logs
: > logs/summary.txt
say() { echo "$*" | tee -a logs/summary.txt; }
status=0

say "RiSC-16 run, $(date -u '+%Y-%m-%d %H:%M UTC'), $(iverilog -V 2>&1 | head -1)"
say ""

# ---- 1. assembler -----------------------------------------------------------
gcc -std=gnu89 -w -include stdlib.h -include ctype.h -o build/asm assembler/a.c \
	|| { say "assembler: build FAILED"; exit 1; }
say "step 1  assembler built (build/asm)"

# ---- 2. assemble ------------------------------------------------------------
for s in software/*.s; do
	n=$(basename "$s" .s)
	build/asm "$s" "images/$n.hex" > /dev/null || { say "step 2  $s: assembler FAILED"; exit 1; }
done
say "step 2  assembled $(ls software/*.s | wc -l) programs into images/"
same() { cmp -s "images/$1.hex" "reference/provided-images/$2" && say "        images/$1.hex == provided $2" \
	|| { say "        images/$1.hex DIFFERS from provided $2"; status=1; }; }
same sys-i      init.sys_i
same usr-i      init.usr_i
same sys-iii-iv init.sys.important
same usr-iii    init_3.usr
say ""

# ---- 3. stages --------------------------------------------------------------
# keep only the per-cycle pipeline state when comparing with a reference log
filt() { tr -d '\r' < "$1" | grep -E '^(-------------|regs |ctl: |-Fetch| tlb1| mem1|-Decode|-Exec| ALU|-Memory| tlb2| mem2|-Write|etc\. |MUXpc|TLB-[AB])' \
	| sed 's/(time 0*\([0-9a-f]\)/(time \1/'; }

# stage <name> <testbench> <defines> <reference log|-> <expected regs|-> <file:image>...
stage() {
	name=$1 tb=$2 defs=$3 ref=$4 want=$5; shift 5
	rm -rf build/run && mkdir build/run
	for m in "$@"; do cp "images/${m#*:}.hex" "build/run/${m%%:*}"; done
	iverilog -g2005 $defs -o build/run/sim "testbench/$tb" design/RiSC.v design/memories.v 2> build/run/compile.txt \
		|| { say "$name: compile FAILED (build/run/compile.txt)"; status=1; return; }
	(cd build/run && vvp -n sim) > "logs/$name.log"
	python3 -I tools/timeline.py "logs/$name.log" > "logs/$name.timeline.txt"
	cyc=$(grep -c '^-Fetch' "logs/$name.log")
	regs=$(grep -B20 'MEMWB_exc=02' "logs/$name.log" | grep '^regs' | tail -1 | cut -c9-)
	line="$name: $cyc cycles"
	if [ -n "$regs" ]; then line="$line, halted, user r1-r7 = $regs"; else line="$line, no halt"; fi
	if [ "$ref" != - ]; then
		f=cat; [ "$name" = stage-1 ] && f="grep -v -E ^(.tlb[12].|TLB-)"	# phase-1 reference used a stub TLB
		filt "reference/$ref" | $f > build/ref.f; filt "logs/$name.log" | $f > build/out.f
		if diff -q build/ref.f build/out.f > /dev/null; then line="$line; every cycle matches $ref"
		else line="$line; DIFFERS from $ref"; status=1; fi
	fi
	if [ "$want" != - ]; then
		if [ "$regs" = "$want" ]; then line="$line; registers correct"
		else line="$line; WRONG, want $want"; status=1; fi
	fi
	say "$line"
}

stage stage-1        test-i.v   ""      ref-phase1.log - init.sys:sys-i      init.usr:usr-i
stage stage-2        test-ii.v  ""      ref-phase2.log - init.sys:sys-ii     init.usr:usr-ii
stage stage-3        test-iii.v ""      ref-phase3.log - init.sys:sys-iii-iv init.usr:usr-iii
stage stage-4-iii    test-iv.v  ""      - "2112 0000 0000 0000 0000 0000 0f00" init.sys:sys-iii-iv init.usr:usr-iii
stage stage-4-dmiss  test-iv.v  ""      - "0001 0002 0003 0004 0c00 0b00 0a00" init.sys:sys-iii-iv init.usr:usr-iv-dmiss
stage stage-4-imiss  test-iv.v  ""      - "0001 0002 0003 0004 000a 000b 000c" init.sys:sys-iii-iv init.usr:usr-iv-imiss
stage stage-5-boot   test-BOOT.v -DBOOT - - init.rom:rom-BOOT init.sys:sys-iii-iv init.usr1:usr-iii

# boot has no halt yet: check that the ROM loaded the OS and entered user code
if grep -q 'reading init.sys into 0000' logs/stage-5-boot.log \
	&& grep -- '^-Fetch' logs/stage-5-boot.log | awk '/PC=7e1e/{f=1;next} f{print;exit}' | grep -q 'PC=0000'; then
	say "        boot ROM ran, loaded the OS from disk, entered user code at 0x0000 (needs a page-fault handler to go further)"
else say "        boot ROM did NOT complete"; status=1; fi
n=$(grep -- '^-Fetch' reference/BOOT-log.txt | awk '{print $2}' > build/b1; grep -- '^-Fetch' logs/stage-5-boot.log | awk '{print $2}' > build/b2; \
	cmp build/b1 build/b2 2>&1 | grep -o 'line [0-9]*' | awk '{print $2-1}')
say "        first $n fetches identical to reference/BOOT-log.txt (its kernel uses different handler addresses after that)"

say ""
[ $status = 0 ] && say "ALL STAGES PASS" || say "SOME STAGES FAILED"
exit $status
