// Exempt path: benchmarks write tracked vars on purpose.
TRACKED(/obj/machinery/pump, bench_declared)

/obj/machinery/pump/proc/bench_writes(obj/machinery/pump/P)
	target_pressure = 1
	P.open = 1
	bench_declared = 2
