// Exempt path: benchmarks build the forbidden things on purpose.
/obj/holder/proc/bench_everything()
	held = null
	stuff += src
	var/datum/callback/cb = CALLBACK(src, PROC_REF(bench_everything))
	var/h = om_handle(src)
	DECLARE_REF(thing)
	own_set(src, "held", src)
	own_set(src, "ghost_in_bench", src)

/obj/holder
	var/bench_handle
