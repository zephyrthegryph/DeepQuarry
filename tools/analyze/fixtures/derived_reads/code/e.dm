/obj/crlf
	var/energy = 1

/obj/crlf/derived()
	. += runs_while(nameof(none))

/obj/crlf/should_run()
	return energy
