/obj/testy
	var/energy = 1

/obj/testy/should_run()
	return energy

/obj/testy/on_state_changed(bits)
	return

/obj/testy/derived()
	. += drawn_from(nameof(energy), nameof(missing))
