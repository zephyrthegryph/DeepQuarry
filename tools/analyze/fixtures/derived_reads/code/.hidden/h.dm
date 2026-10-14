/obj/hid
	var/energy = 1

/obj/hid/derived()
	. += runs_while(nameof(energy))

/obj/hid/should_run()
	return energy + 1
