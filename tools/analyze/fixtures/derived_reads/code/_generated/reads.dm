// pretend generated file: never scanned
/obj/gen
	var/energy = 1

/obj/gen/derived()
	. += runs_while(nameof(none))

/obj/gen/should_run()
	return energy
