// Arena slot leak (doc/rewrite/ownership.md §8): every /datum/gas_mixture holds a Rust arena slot,
// freed only when the mixture is destroyed. A mixture nobody owns (an orphan) is dropped by BYOND
// without Destroy() and its slot leaks. These tests build and tear down pipe machinery and
// networks, then ask the arena (vg_gas_retain_mixtures()) how many slots no live datum names.

/// Every live gas mixture datum that still holds a slot.
/proc/dq_gas_arena_live_mixtures()
	. = list()
	for(var/datum/gas_mixture/mix)
		if(!isnull(mix._extools_pointer_gasmixture))
			. += mix

/// How many live mixtures are not being destroyed.
/proc/dq_gas_arena_live_count()
	. = 0
	for(var/datum/gas_mixture/mix as anything in dq_gas_arena_live_mixtures())
		if(!QDELETED(mix))
			.++

/datum/unit_test/dq_gas_arena_slots_return_to_baseline

/datum/unit_test/dq_gas_arena_slots_return_to_baseline/Run()
	// Baseline: drop slots that were already stale, then count what is alive.
	vg_gas_retain_mixtures(dq_gas_arena_live_mixtures())
	var/baseline_live = dq_gas_arena_live_count()

	var/list/run = dq_atmos_test_find_clear_pipe_run(3)
	TEST_ASSERT_NOTNULL(run, "no clear floor run for the arena leak test")
	var/turf/A = run[1]
	var/turf/B = run[2]
	var/turf/C = run[3]
	var/axis = get_dir(A, B) | get_dir(B, A)

	// pipe - pump - pipe: a binary device between two pipelines (PROTO ports bound to the
	// region mixtures, private until bound).
	var/obj/machinery/atmospherics/pipe/simple/P1 = new(A)
	P1.dir = axis
	P1.initialize_directions = axis
	var/obj/machinery/atmospherics/binary/pump/pump = new(B, get_dir(A, B))
	var/obj/machinery/atmospherics/pipe/simple/P2 = new(C)
	P2.dir = axis
	P2.initialize_directions = axis
	var/list/machines = list(P1, pump, P2)
	for(var/obj/machinery/atmospherics/machine as anything in machines)
		machine.atmos_init()
	dq_atmos_test_publish_rust_pipenets(machines)
	TEST_ASSERT_NOTNULL(P1.parent, "the fixture pipe did not join a pipeline")

	// Unconnected devices of every port family: unary, trinary, omni, and a turbine.
	var/list/loose = list(
		new /obj/machinery/atmospherics/unary/vent_pump(A),
		new /obj/machinery/atmospherics/trinary/mixer(B),
		new /obj/machinery/atmospherics/omni/mixer(C),
		new /obj/machinery/atmospherics/pipeturbine(A),
	)

	// Two legacy networks merged, and one rebuilt from member mixtures.
	var/datum/pipe_network/receiver = new
	own_set(receiver, "air", new /datum/gas_mixture(70))
	var/datum/pipe_network/donor = new
	own_set(donor, "air", new /datum/gas_mixture(70))
	receiver.merge(donor)
	TEST_ASSERT(QDELETED(donor), "the merged donor network survived")

	// Teardown.
	for(var/obj/machinery/atmospherics/machine as anything in machines + loose)
		qdel(machine)
	qdel(receiver)
	SSair.rust_commit_pending_pipenets()

	var/leaked = vg_gas_retain_mixtures(dq_gas_arena_live_mixtures())
	TEST_ASSERT_EQUAL(leaked, 0, "[leaked] arena slot(s) lost their gas mixture without it being destroyed (an orphaned mixture)")
	var/after_live = dq_gas_arena_live_count()
	TEST_ASSERT(after_live <= baseline_live, "live gas mixtures went from [baseline_live] to [after_live]: a destroyed machine or network left a mixture alive")
