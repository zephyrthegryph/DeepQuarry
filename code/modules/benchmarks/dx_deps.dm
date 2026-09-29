// The cost of a tracked change with and without declared dependencies (code/datums/capabilities/derived.dm):
// N machines of a type that declares nothing (any change re-derives everything) and N of a type that
// declares drawn_from(bench_a). Each round writes a var nobody reads (bench_noise), then one that draw()
// reads (bench_a), on every machine, and flushes.
// Run: tools/build/build.sh bench --scenario=dx_deps [--bench_count=1000] [--bench_rounds=20]

/obj/machinery/dx_deps_bench_legacy
	name = "deps benchmark machine (undeclared)"
	var/bench_a = 0
	var/bench_noise = 0

TRACKED(/obj/machinery/dx_deps_bench_legacy, bench_a, CHANGE_MACHINE_SETTINGS)
TRACKED(/obj/machinery/dx_deps_bench_legacy, bench_noise, CHANGE_MACHINE_SETTINGS)

/obj/machinery/dx_deps_bench_legacy/draw(datum/look/look)
	..()
	// ALLOW(derived_reads): the undeclared type is the baseline this scenario measures
	look.state("deps_[bench_a % 4]")

/// The same draw(), with its read declared.
/obj/machinery/dx_deps_bench_legacy/declared
	name = "deps benchmark machine (declared)"

/obj/machinery/dx_deps_bench_legacy/declared/derived()
	. = ..()
	. += drawn_from(nameof(bench_a))

/datum/benchmark/dx_deps
	id = "dx_deps"
	description = "Declared dependencies: N undeclared and N declared machines, R rounds of an unread write and a read write each"

/// One round per pass: `noise` writes bench_noise on every machine, otherwise bench_a; then a flush.
/datum/benchmark/dx_deps/proc/write_rounds(list/machines, rounds, noise)
	var/start = REALTIMEOFDAY
	for(var/round in 1 to rounds)
		for(var/obj/machinery/dx_deps_bench_legacy/M as anything in machines)
			if(noise)
				M.set_bench_noise(round)
			else
				M.set_bench_a(round)
		refresh_flush()
	return (REALTIMEOFDAY - start) * 100 // ms

/datum/benchmark/dx_deps/Run()
	var/count = param("count", 1000)
	var/rounds = param("rounds", 20)
	var/list/legacy = list()
	var/list/exact = list()
	var/turf/origin = locate(10, 10, 1)
	for(var/i in 1 to count)
		legacy += new /obj/machinery/dx_deps_bench_legacy(locate(origin.x + (i % 60), origin.y + round(i / 60) % 60, origin.z))
		exact += new /obj/machinery/dx_deps_bench_legacy/declared(locate(origin.x + (i % 60), origin.y + round(i / 60) % 60, origin.z))
	refresh_flush()
	var/drained = GLOB.refresh_bench_drained
	metric("legacy_unread_write_ms", write_rounds(legacy, rounds, TRUE), "ms")
	count_metric("legacy_unread_refreshes", GLOB.refresh_bench_drained - drained, "refreshes")
	drained = GLOB.refresh_bench_drained
	metric("exact_unread_write_ms", write_rounds(exact, rounds, TRUE), "ms")
	count_metric("exact_unread_refreshes", GLOB.refresh_bench_drained - drained, "refreshes")
	drained = GLOB.refresh_bench_drained
	metric("legacy_read_write_ms", write_rounds(legacy, rounds, FALSE), "ms")
	count_metric("legacy_read_refreshes", GLOB.refresh_bench_drained - drained, "refreshes")
	drained = GLOB.refresh_bench_drained
	metric("exact_read_write_ms", write_rounds(exact, rounds, FALSE), "ms")
	count_metric("exact_read_refreshes", GLOB.refresh_bench_drained - drained, "refreshes")
	for(var/obj/machinery/dx_deps_bench_legacy/M as anything in legacy + exact)
		qdel(M) // ALLOW(lifecycle): the benchmark deletes the machines it made
