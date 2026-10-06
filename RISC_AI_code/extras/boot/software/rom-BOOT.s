#
# boot ROM - compile into "init.rom"
#

	movi	r1, 0x7f10	# IO address

	movi	r2, 3		# file number argument: 3 is the OS
	sw	r2, r1, 1	# write argument to IO register

	sw	r0, r1, 2	# argument 2 = memory address (OS loads at 0)

	movi	r2, 0x1234	# disk-read request
	sw	r2, r1, 0	# write request to IO register

	movi	r3, 1		# the value IO_REQ_DONE
wait:	lw	r2, r1, 3	# read value from disk's status register
	bne	r2, r3, wait	# loop until the disk is done

#
# at this point, the OS is loaded.
# now, load a single user process (e.g., the shell): first, set up an ASID & root PTE and jump to virtual address 0.
# the TLB-miss handler will load an invalid table entry and call the page-fault handler, which will load the code
#

	movi	r1, 1		# where is the executable file?
	sw	r1, r0, 1	# tell the OS what the file number is
	movi	r1, 17		# pick an ASID
	sw	r1, r0, 0	# tell the OS what the ASID is
	movi	r2, 192		# base address of root page table
	add	r2, r1, r2	# RPT base + ASID = address of root PTE for process = ASID
	movi	r1, 0x8002	# put the user page table into physical page 2
	sw	r1, r2, 0	# this sets up the kernel page-table entry, which is enough
	lli	r4, 17		# context switch to ASID 9
	rfe	r0		# jump to user code

