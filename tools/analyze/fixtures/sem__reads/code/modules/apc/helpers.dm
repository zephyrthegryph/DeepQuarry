// Global helpers: annotated (followed through the argument) and not.
/proc/cell_charge_percent(obj/item/cell/C)
	READS_FROM(C)
	return C ? 100 * C.charge / C.maxcharge : 0

/proc/pure_math(x)
	READS_FROM()
	return x * 2

/proc/unannotated_helper(obj/item/cell/C)
	return C ? C.charge : 0

/proc/two_arg_helper(obj/item/cell/C, mult)
	READS_FROM(C)
	return C.charge * mult
