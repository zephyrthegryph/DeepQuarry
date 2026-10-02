/obj/machinery/skip2/machine_step(dt)
	if(!on) return PROCESS_KILL

OM_DERIVE_FIELD(/obj/machinery/skipdv, inputs, list("gamma"))

/obj/machinery/skipdv/proc/derived_skip()
	gamma = 1
	changed(src, CHANGE_X)
