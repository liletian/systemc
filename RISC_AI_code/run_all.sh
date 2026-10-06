#!/bin/sh
# Run every step and collect the results into summary.txt.
# Each step can also be run on its own: stepN_*/run.sh
# Needs: gcc, Icarus Verilog 12 (iverilog, vvp), python3.
cd "$(dirname "$0")"
status=0
: > summary.txt
for s in step1_simple step2_pipeline step3_tlb_kmiss step4_tlb_umiss extras/boot; do
	./$s/run.sh > /dev/null || status=1
	echo "=== $s" >> summary.txt
	cat $s/logs/summary.txt >> summary.txt
	echo >> summary.txt
done

# the sources reproduce the memory images that came with the course
echo "=== assembled images vs course-provided images" >> summary.txt
for p in step3_tlb_kmiss/images/sys-i.hex:init.sys_i step3_tlb_kmiss/images/usr-i.hex:init.usr_i \
         step4_tlb_umiss/images/sys-iii-iv.hex:init.sys.important step4_tlb_umiss/images/usr-iii.hex:init_3.usr; do
	if cmp -s "${p%%:*}" "reference/provided-images/${p#*:}"; then echo "${p%%:*} == ${p#*:}" >> summary.txt
	else echo "${p%%:*} DIFFERS from ${p#*:}" >> summary.txt; status=1; fi
done
echo >> summary.txt
grep -E '^(=== |PASS|FAIL)' summary.txt | paste - - | grep -v 'assembled images' | sed 's/=== //'
[ $status = 0 ] && echo "ALL STEPS PASS" | tee -a summary.txt || echo "SOME STEPS FAILED" | tee -a summary.txt
exit $status
