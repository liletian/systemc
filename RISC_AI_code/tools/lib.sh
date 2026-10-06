# Shared helpers for the step run.sh scripts. Sourced, not run.
#
# A step folder holds design/, software/ and testbench/. Its run.sh calls:
#   setup "title"                      start logs/summary.txt, build the assembler, assemble software/*.s into images/
#   run_tb NAME TESTBENCH "DEFINES" [FILE:IMAGE ...]
#                                      copy images/IMAGE.hex to FILE, compile TESTBENCH with design/*.v, run it
#                                      into logs/NAME.log
#   check_full NAME REF|- REGS|-       for the full RiSC.v (steps 3, 4): halted?, compare with reference/REF,
#                                      compare the user registers at halt with REGS; writes logs/NAME.timeline.txt
#   check_simple NAME REGS DATA        for steps 1, 2: halted?, final registers and data word
#   finish                             print PASS / FAIL and exit with the status

STEP=$(pwd)
ROOT=$(cd .. && pwd); [ -d "$ROOT/assembler" ] || ROOT=$(cd ../.. && pwd)
ASM=$ROOT/build/asm
status=0

say() { echo "$*" | tee -a logs/summary.txt; }

setup() {
	mkdir -p images logs "$ROOT/build"
	: > logs/summary.txt
	say "$1"
	say "run $(date -u '+%Y-%m-%d %H:%M UTC'), $(iverilog -V 2>&1 | head -1)"
	say ""
	if [ ! -x "$ASM" ] || [ "$ROOT/assembler/a.c" -nt "$ASM" ]; then
		gcc -std=gnu89 -w -include stdlib.h -include ctype.h -o "$ASM" "$ROOT/assembler/a.c" || { say "assembler build FAILED"; exit 1; }
	fi
	for s in software/*.s; do
		"$ASM" "$s" "images/$(basename "$s" .s).hex" > /dev/null || { say "assembling $s FAILED"; exit 1; }
	done
	say "assembled: $(cd software && ls *.s | tr '\n' ' ')"
	say ""
}

run_tb() {
	name=$1 tb=$2 defs=$3; shift 3
	dir="$ROOT/build/$(basename "$STEP")-$name"
	rm -rf "$dir" && mkdir -p "$dir"
	for m in "$@"; do cp "images/${m#*:}.hex" "$dir/${m%%:*}"; done
	iverilog -g2005 $defs -o "$dir/sim" "testbench/$tb" "${DESIGN:-design}/RiSC.v" "${DESIGN:-design}/memories.v" 2> "$dir/compile.txt" \
		|| { say "$name: compile FAILED, see $dir/compile.txt"; status=1; return 1; }
	(cd "$dir" && vvp -n sim) > "logs/$name.log"
}

# keep only the per-cycle pipeline state, so logs from different simulators compare
filt() { tr -d '\r' < "$1" | grep -E '^(-------------|regs |ctl: |-Fetch| tlb1| mem1|-Decode|-Exec| ALU|-Memory| tlb2| mem2|-Write|etc\. |MUXpc|TLB-[AB])' \
	| sed 's/(time 0*\([0-9a-f]\)/(time \1/'; }

check_full() {
	name=$1 ref=$2 want=$3
	[ -f "logs/$name.log" ] || return
	python3 -I "$ROOT/tools/timeline.py" "logs/$name.log" > "logs/$name.timeline.txt"
	cyc=$(grep -c '^-Fetch' "logs/$name.log")
	regs=$(grep -B20 'MEMWB_exc=02' "logs/$name.log" | grep '^regs' | tail -1 | cut -c9-)
	ctl=$(grep -B20 'MEMWB_exc=02' "logs/$name.log" | grep '^ctl' | tail -1 | cut -c9-)
	if [ -n "$regs" ]; then line="$name: halted after $cyc cycles; user r1-r7 = $regs; cr1-cr7 = $ctl"
	else line="$name: $cyc cycles, NO HALT"; status=1; fi
	if [ "$ref" != - ]; then
		f=cat; case "$ref" in *phase1*) f="grep -v -E ^(.tlb[12].|TLB-)";; esac	# phase-1 reference used a stub TLB
		filt "$ROOT/reference/$ref" | $f > "$ROOT/build/ref.f"; filt "logs/$name.log" | $f > "$ROOT/build/out.f"
		if diff -q "$ROOT/build/ref.f" "$ROOT/build/out.f" > /dev/null; then line="$line; every cycle matches $ref"
		else line="$line; DIFFERS from $ref"; status=1; fi
	fi
	if [ "$want" != - ]; then
		case "$want" in
			cr:*) got=$ctl; want=${want#cr:};;
			*)    got=$regs;;
		esac
		if [ "$got" = "$want" ]; then line="$line; expected registers: yes"
		else line="$line; expected registers: NO (want $want)"; status=1; fi
	fi
	say "$line"
}

check_simple() {
	name=$1 want=$2 data=$3
	got=$(grep '^final regs' "logs/$name.log" | sed 's/.*: //')
	mem=$(grep '(data) =' "logs/$name.log" | sed 's/.*= //')
	cyc=$(grep '^HALT after' "logs/$name.log" | awk '{print $3}')
	if [ -z "$got" ]; then say "$name: NO HALT"; status=1; return; fi
	line="$name: halted after $cyc cycles; r1-r7 = $got; mem[data] = $mem"
	if [ "$got" = "$want" ] && [ "$mem" = "$data" ]; then line="$line; expected values: yes"
	else line="$line; expected values: NO (want $want, $data)"; status=1; fi
	say "$line"
}

finish() {
	say ""
	[ $status = 0 ] && say "PASS" || say "FAIL"
	exit $status
}
