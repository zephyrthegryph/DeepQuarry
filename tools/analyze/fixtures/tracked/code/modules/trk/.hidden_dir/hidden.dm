// A dot directory: glob.glob skips it, so neither its declarations nor its writes count.
TRACKED(/obj/machinery/pump, hidden_declared)

/obj/machinery/pump/proc/hidden_writes()
	target_pressure = 1
	hidden_declared = 2
