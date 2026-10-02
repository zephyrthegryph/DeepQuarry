/obj/blocks
/*
	process()
	START_PROCESSING(x)
*/
	process()
/* single line block */
	process()
	/* c */ START_PROCESSING(x)
/* opens
	START_PROCESSING(x)
closes */
	START_PROCESSING(y)
	/* opens here
	process()
	START_PROCESSING(z)
 * closes */ process()
/obj/after
	process()
/*
/obj/skipped_type_line
*/
	process()
	var/s = "/* not a block"
	process()
