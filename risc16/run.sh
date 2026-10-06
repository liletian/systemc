#!/bin/sh
# Build and run all three phases with Icarus Verilog and diff each against its reference log.
# Only the per-cycle pipeline state is compared (banners, MEMORY dumps and "kmode:" lines are dropped).
cd "$(dirname "$0")"
filt() { tr -d '\r' < "$1" \
	| grep -E '^(-------------|regs |ctl: |-Fetch| tlb1| mem1|-Decode|-Exec| ALU|-Memory| tlb2| mem2|-Write|etc\. |MUXpc|TLB-[AB])' \
	| sed 's/(time 0*\([0-9a-f]\)/(time \1/'; }
# the phase-1 reference was produced with a stub TLB, so its TLB debug lines are not comparable
filt1() { filt "$1" | grep -v -E '^( tlb[12] |TLB-[AB])'; }
status=0
for p in 1 2 3; do
	iverilog -g2005 -DPHASE$p -o sim$p test.v RiSC.v memories.v 2>/dev/null || exit 1
	vvp -n sim$p > out$p.log
	if [ $p = 1 ]; then f=filt1; else f=filt; fi
	$f ref-phase$p.log > ref$p.f
	$f out$p.log > out$p.f
	if diff -q ref$p.f out$p.f >/dev/null; then
		echo "phase $p: MATCH ($(grep -c -- '^-Fetch' out$p.f) cycles)"
	else
		echo "phase $p: DIFF  (see: diff ref$p.f out$p.f)"; status=1
	fi
done
# phase 4: no reference log, so check that each program halts with the expected user registers
for t in "init_3.usr:2112 0000 0000 0000 0000 0000 0f00" \
         "usr-iv-dmiss.hex:0001 0002 0003 0004 0c00 0b00 0a00" \
         "usr-iv-imiss.hex:0001 0002 0003 0004 000a 000b 000c"; do
	u=${t%%:*}; want=${t#*:}
	iverilog -g2005 -DPHASE4 -DUSR="\"$u\"" -o sim4 test.v RiSC.v memories.v 2>/dev/null || exit 1
	got=$(vvp -n sim4 | grep -B20 'MEMWB_exc=02' | grep '^regs' | tail -1 | cut -c9-)
	if [ "$got" = "$want" ]; then echo "phase 4 ($u): MATCH (halts, regs $got)"
	else echo "phase 4 ($u): FAIL (regs: ${got:-no halt}, want $want)"; status=1; fi
done
rm -f sim1 sim2 sim3 sim4
exit $status
