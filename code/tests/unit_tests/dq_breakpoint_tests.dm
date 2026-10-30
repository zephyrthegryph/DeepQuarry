// D4 (damage.md §6): declarative breakpoints, the one machinery break,
// destruction debris and generated damage flavour. The generated threshold
// tests for these rules live in dq_rule_tests.dm (dq_rule_thresholds).

/obj/machinery/dq_breakpoint_probe
	max_integrity = 100
	integrity_failure = 0.5
	var/break_calls = 0
	var/fix_calls = 0

/obj/machinery/dq_breakpoint_probe/proc/count_break(datum/act/A)
	break_calls++

CAPABILITIES(/obj/machinery/dq_breakpoint_probe)
	on_notice(/datum/notice/atom_broken, then(PROC_REF(count_break)))

/obj/machinery/dq_breakpoint_probe/atom_fix()
	. = ..()
	fix_calls++

/// machinery_broken event listener.
/datum/dq_breakpoint_listener
	var/heard = 0
	var/last_flag

/datum/dq_breakpoint_listener/proc/on_broken(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/machinery_broken/event = N
	heard++
	last_flag = event.damage_flag

// ---- One path: the break/destroy default is native and binds nothing ----

/datum/unit_test/dq_breakpoint_single_path

/datum/unit_test/dq_breakpoint_single_path/Run()
	// No rule declares a breakpoint or a damage band, so these types carry no rules and no per-object binding.
	for(var/path in list(/obj/machinery/computer, /obj/structure/grille, /obj/structure/window, /obj/structure/railing, /obj/machinery/door/airlock))
		TEST_ASSERT_NULL(dq_rules_for_type(path), "[path] declares no rules: its break and destroy are the native default")
	TEST_ASSERT_NULL(dq_rules_for_type(/obj/item/dq_rule_test), "an object without breakpoints has no rules")
	TEST_ASSERT(dq_damage_flavour_declared(/obj/structure/window), "windows declare damage flavour")
	TEST_ASSERT(!dq_damage_flavour_declared(/obj/machinery/computer), "computers do not")
	var/turf/T = dq_containment_floor()
	var/obj/machinery/dq_breakpoint_probe/probe = allocate(/obj/machinery/dq_breakpoint_probe, T)
	TEST_ASSERT_NULL(dq_rule_binding_of(probe), "a machine with a breaking point needs no binding")
	var/obj/structure/grille/grille = allocate(/obj/structure/grille, T)
	TEST_ASSERT_NULL(dq_rule_binding_of(grille), "nor does a grille")
	// A materialized and a sandboxed object take the same path with the same outcome.
	var/obj/machinery/dq_breakpoint_probe/sandboxed = new_unmaterialized(/obj/machinery/dq_breakpoint_probe, T)
	for(var/obj/machinery/dq_breakpoint_probe/subject in list(probe, sandboxed))
		subject.take_damage(60, BRUTE, MELEE, FALSE)
		TEST_ASSERT_EQUAL(subject.break_calls, 1, "[subject.type] crossing its breaking point breaks once, bound or not")
		TEST_ASSERT(!QDELETED(subject), "and does not destroy")
	qdel(sandboxed)
	own_turf_contents(T) // breaking throws sparks

/// A sample of formerly-legacy and formerly-rule types: break at the declared fraction (when declared), destroy at zero, each exactly on the crossing.
/datum/unit_test/dq_breakpoint_sweep_outcomes

/datum/unit_test/dq_breakpoint_sweep_outcomes/Run()
	var/turf/T = dq_containment_floor()
	var/list/sample = list(/obj/structure/window, /obj/structure/railing, /obj/structure/table, /obj/structure/grille, /obj/machinery/computer, /obj/machinery/door/airlock, /obj/machinery/dq_breakpoint_probe)
	for(var/path in sample)
		var/obj/subject = allocate(path, T)
		if(!subject.uses_integrity)
			continue
		var/failure_amount = subject.integrity_failure * subject.max_integrity
		var/expect_breaks = subject.integrity_failure > 0 ? 1 : 0
		var/datum/dq_breakpoint_counter/counter = new
		observe(subject, /datum/notice/atom_broken, counter, then(TYPE_PROC_REF(/datum/dq_breakpoint_counter, on_broken)))
		if(expect_breaks)
			var/to_above = subject.max_integrity - failure_amount - 1
			if(to_above > 0)
				subject.take_damage(to_above, BRUTE, "", FALSE)
				TEST_ASSERT_EQUAL(counter.heard, 0, "[path]: above the breaking point nothing breaks")
		TEST_ASSERT(!QDELETED(subject), "[path]: not destroyed above zero")
		subject.take_damage(subject.max_integrity * 2, BRUTE, "", FALSE)
		TEST_ASSERT(QDELETED(subject), "[path]: destroyed once integrity reaches zero")
		TEST_ASSERT_EQUAL(counter.heard, expect_breaks, "[path]: the break fires exactly once over the whole fall, when declared")
		qdel(counter)
		own_turf_contents(T)

/datum/dq_breakpoint_counter
	var/heard = 0

/datum/dq_breakpoint_counter/proc/on_broken(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	heard++

// ---- Parity: machines breaking and being fixed ----

/datum/unit_test/dq_machine_break_parity

/datum/unit_test/dq_machine_break_parity/Run()
	var/turf/T = dq_containment_floor()
	var/datum/dq_breakpoint_listener/listener = new
	var/obj/machinery/dq_breakpoint_probe/probe = allocate(/obj/machinery/dq_breakpoint_probe, T)
	observe(probe, /datum/notice/machinery_broken, listener, then(TYPE_PROC_REF(/datum/dq_breakpoint_listener, on_broken)))
	TEST_ASSERT_NULL(dq_rule_binding_of(probe), "a machine with a breaking point needs no binding")

	probe.take_damage(40, BRUTE, MELEE, FALSE)
	TEST_ASSERT(!probe.broken_now(), "above the breaking point it is not broken")
	probe.take_damage(20, BRUTE, MELEE, FALSE)
	TEST_ASSERT(probe.broken_now(), "crossing the breaking point sets BROKEN in the same call")
	TEST_ASSERT_EQUAL(probe.break_calls, 1, "atom_break ran once")
	TEST_ASSERT_EQUAL(listener.heard, 1, "machinery_broken was sent once")
	TEST_ASSERT_EQUAL(listener.last_flag, MELEE, "with the damage flag")
	probe.take_damage(10, BRUTE, MELEE, FALSE)
	dq_rx_flush()
	TEST_ASSERT_EQUAL(probe.break_calls, 1, "further damage does not break it again")

	probe.repair_damage(100)
	TEST_ASSERT(!probe.broken_now(), "repair above the breaking point clears BROKEN")
	TEST_ASSERT_EQUAL(probe.fix_calls, 1, "atom_fix ran once")
	probe.take_damage(60, BRUTE, MELEE, FALSE)
	TEST_ASSERT_EQUAL(probe.break_calls, 2, "repaired, it breaks again")
	TEST_ASSERT_EQUAL(listener.heard, 2, "and signals again")

	// Breaking an already-broken machine changes nothing.
	TEST_ASSERT(!probe.atom_break(), "atom_break on a broken machine returns FALSE")
	TEST_ASSERT_EQUAL(listener.heard, 2, "and sends no signal")

	// One hit that both breaks and destroys: break first, then destruction.
	var/obj/machinery/dq_breakpoint_probe/second = allocate(/obj/machinery/dq_breakpoint_probe, T)
	second.take_damage(200, BRUTE, MELEE, FALSE)
	TEST_ASSERT_EQUAL(second.break_calls, 1, "a destroying hit still breaks first")
	TEST_ASSERT(QDELETED(second), "and then destroys it")

	// A sandboxed machine takes the same path.
	var/obj/machinery/dq_breakpoint_probe/sandboxed = new_unmaterialized(/obj/machinery/dq_breakpoint_probe, T)
	TEST_ASSERT_NULL(dq_rule_binding_of(sandboxed), "an unmaterialized machine has no binding")
	sandboxed.take_damage(60, BRUTE, MELEE, FALSE)
	TEST_ASSERT(sandboxed.broken_now(), "it still breaks")
	TEST_ASSERT_EQUAL(sandboxed.break_calls, 1, "once")
	qdel(sandboxed)
	qdel(listener)
	own_turf_contents(T) // breaking throws sparks

/// Real machines through the base break: the flag, the signal, the fix.
/datum/unit_test/dq_machine_break_real_types

/datum/unit_test/dq_machine_break_real_types/Run()
	var/turf/T = dq_containment_floor()
	var/datum/dq_breakpoint_listener/listener = new
	for(var/path in list(/obj/machinery/computer, /obj/machinery/door/airlock, /obj/machinery/station_map, /obj/machinery/camera))
		var/obj/machinery/machine = allocate(path, T)
		listener.heard = 0
		observe(machine, /datum/notice/machinery_broken, listener, then(TYPE_PROC_REF(/datum/dq_breakpoint_listener, on_broken)))
		TEST_ASSERT(machine.atom_break(), "[path]: breaks")
		TEST_ASSERT(machine.broken_now(), "[path]: BROKEN is set")
		TEST_ASSERT_EQUAL(listener.heard, 1, "[path]: the signal is sent")
		TEST_ASSERT(machine.atom_fix(), "[path]: is fixed")
		TEST_ASSERT(!machine.broken_now(), "[path]: BROKEN is cleared")
		unobserve(machine, /datum/notice/machinery_broken, listener)
		qdel(machine)
		own_turf_contents(T) // breaking throws sparks
	qdel(listener)

// ---- Flavour text at each band ----

/datum/unit_test/dq_damage_flavour_bands

/datum/unit_test/dq_damage_flavour_bands/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/viewer = allocate(/mob/living/carbon/human, T)
	var/obj/structure/railing/railing = allocate(/obj/structure/railing, T)
	TEST_ASSERT_NULL(dq_rule_binding_of(railing), "railings need no binding for their damage flavour")
	var/list/steps = list(1, 0.7, 0.45, 0.2, 0.6, 0.9, 0.1)
	var/list/bands = list(DAMAGE_BAND_NONE, DAMAGE_BAND_LIGHT, DAMAGE_BAND_MODERATE, DAMAGE_BAND_HEAVY, DAMAGE_BAND_LIGHT, DAMAGE_BAND_NONE, DAMAGE_BAND_HEAVY)
	for(var/i in 1 to length(steps))
		var/ratio = steps[i]
		var/band = bands[i]
		railing.update_integrity(ratio * railing.max_integrity)
		TEST_ASSERT_EQUAL(dq_damage_band_for(railing), band, "at [ratio] integrity the band is [band]")
		var/text = jointext(railing.examine(viewer), "\n")
		var/line = railing.damage_flavour_text(band)
		if(line)
			TEST_ASSERT(findtext(text, line), "at [ratio] examine shows the band's line")
		for(var/other in list(DAMAGE_BAND_LIGHT, DAMAGE_BAND_MODERATE, DAMAGE_BAND_HEAVY))
			if(other != band)
				TEST_ASSERT(!findtext(text, railing.damage_flavour_text(other)), "at [ratio] examine shows no other band's line")

	// Sandboxed objects read the same levels.
	var/obj/structure/railing/sandboxed = new_unmaterialized(/obj/structure/railing, T)
	for(var/i in 1 to length(steps))
		sandboxed.update_integrity(steps[i] * sandboxed.max_integrity)
		TEST_ASSERT_EQUAL(dq_damage_band_for(sandboxed), bands[i], "unbound at [steps[i]]: band [bands[i]]")
	qdel(sandboxed)

	// The lines are generated from the type's wear.
	var/obj/structure/window/window = allocate(/obj/structure/window, T)
	TEST_ASSERT(findtext(window.damage_flavour_text(DAMAGE_BAND_LIGHT), "cracks"), "windows show cracks")
	TEST_ASSERT(findtext(railing.damage_flavour_text(DAMAGE_BAND_LIGHT), "scrapes and dents"), "others show scrapes and dents")
	TEST_ASSERT_NULL(railing.damage_flavour_text(DAMAGE_BAND_NONE), "intact shows nothing")

// ---- Destruction: debris, then drop policies ----

/datum/unit_test/dq_destruction_debris

/datum/unit_test/dq_destruction_debris/Run()
	var/turf/T = dq_containment_floor()
	for(var/obj/item/stack/rods/R in turf_contents_of_type(T, /obj/item/stack/rods))
		qdel(R)
	var/obj/structure/railing/railing = allocate(/obj/structure/railing, T)
	railing.take_damage(railing.max_integrity * 2, BRUTE, MELEE, FALSE)
	TEST_ASSERT(QDELETED(railing), "the railing is destroyed")
	var/rods = 0
	for(var/obj/item/stack/rods/R in turf_contents_of_type(T, /obj/item/stack/rods))
		rods += R.get_amount()
		qdel(R)
	TEST_ASSERT_EQUAL(rods, 1, "its debris entry drops one rod")
