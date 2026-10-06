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
rm -f sim1 sim2 sim3
exit $status
