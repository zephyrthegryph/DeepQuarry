// D4 (damage.md §6): declarative breakpoints, the one machinery break,
// destruction debris and generated damage flavour. The generated threshold
// tests for these rules live in dq_rule_tests.dm (dq_rule_thresholds).

/obj/machinery/dq_breakpoint_probe
	max_integrity = 100
	integrity_failure = 0.5
	var/break_calls = 0
	var/fix_calls = 0

/obj/machinery/dq_breakpoint_probe/atom_break(damage_flag)
	. = ..()
	break_calls++

/obj/machinery/dq_breakpoint_probe/atom_fix()
	. = ..()
	fix_calls++

/// COMSIG_MACHINERY_BROKEN listener.
/datum/dq_breakpoint_listener
	var/heard = 0
	var/last_flag

/datum/dq_breakpoint_listener/proc/on_broken(obj/machinery/source, damage_flag)
	SIGNAL_HANDLER
	heard++
	last_flag = damage_flag

// ---- The rules are declared and picked up by the generator ----

/datum/unit_test/dq_breakpoint_rules_declared

/datum/unit_test/dq_breakpoint_rules_declared/Run()
	var/list/rules = dq_rules()
	var/datum/rule/breaks = rules[/datum/rule/integrity_breaks]
	var/datum/rule/destroyed = rules[/datum/rule/integrity_destroyed]
	TEST_ASSERT(breaks, "the breaking-point rule is registered")
	TEST_ASSERT(destroyed, "the destroyed rule is registered")
	for(var/path in list(/datum/rule/damage_flavour/light, /datum/rule/damage_flavour/moderate, /datum/rule/damage_flavour/heavy))
		var/datum/rule/flavour = rules[path]
		TEST_ASSERT(flavour, "[path] is registered")
		TEST_ASSERT_EQUAL(length(flavour.thresholds()), 1, "[path] declares one threshold")
	TEST_ASSERT_EQUAL(length(dq_damage_flavour_rules()), 3, "three flavour bands")

	// Only types that declare a breakpoint get the rules; plain objects cost nothing.
	TEST_ASSERT(breaks in dq_rules_for_type(/obj/machinery/computer), "computers break by rule")
	TEST_ASSERT(breaks in dq_rules_for_type(/obj/structure/grille), "grilles break by rule")
	TEST_ASSERT(!(breaks in dq_rules_for_type(/obj/structure/window)), "windows declare no breaking point")
	TEST_ASSERT(destroyed in dq_rules_for_type(/obj/structure/window), "windows have damage flavour, so their destruction is a rule too")
	TEST_ASSERT_NULL(dq_rules_for_type(/obj/item/dq_rule_test), "an object without breakpoints has no rules")

	// The generator instantiates each type that declares a breakpoint.
	var/list/declaring = dq_rule_declaring_types(breaks, /obj)
	TEST_ASSERT(/obj/machinery/dq_breakpoint_probe in declaring, "the generator covers the probe machine")
	TEST_ASSERT(/obj/machinery/computer in declaring, "and computers")
	TEST_ASSERT(!(/obj/machinery/computer/pandemic in declaring), "but not subtypes that inherit the level")
	TEST_ASSERT(/obj/structure/window in dq_rule_declaring_types(rules[/datum/rule/damage_flavour/light], /obj/structure/window), "flavour covers its roots")

// ---- Parity: machines breaking and being fixed ----

/datum/unit_test/dq_machine_break_parity

/datum/unit_test/dq_machine_break_parity/Run()
	var/turf/T = test_floor()
	var/datum/dq_breakpoint_listener/listener = new
	var/obj/machinery/dq_breakpoint_probe/probe = allocate(/obj/machinery/dq_breakpoint_probe, T)
	listener.RegisterSignal(probe, COMSIG_MACHINERY_BROKEN, TYPE_PROC_REF(/datum/dq_breakpoint_listener, on_broken))
	TEST_ASSERT(dq_rule_binding_of(probe), "a machine with a breaking point subscribes its rules")

	probe.take_damage(40, BRUTE, MELEE, FALSE)
	TEST_ASSERT(!(probe.stat & BROKEN), "above the breaking point it is not broken")
	probe.take_damage(20, BRUTE, MELEE, FALSE)
	TEST_ASSERT(probe.stat & BROKEN, "crossing the breaking point sets BROKEN in the same call")
	TEST_ASSERT_EQUAL(probe.break_calls, 1, "atom_break ran once")
	TEST_ASSERT_EQUAL(listener.heard, 1, "COMSIG_MACHINERY_BROKEN was sent once")
	TEST_ASSERT_EQUAL(listener.last_flag, MELEE, "with the damage flag")
	probe.take_damage(10, BRUTE, MELEE, FALSE)
	dq_rx_flush()
	TEST_ASSERT_EQUAL(probe.break_calls, 1, "further damage does not break it again")

	probe.repair_damage(100)
	TEST_ASSERT(!(probe.stat & BROKEN), "repair above the breaking point clears BROKEN")
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

	// A sandboxed machine has no binding and keeps the legacy crossing.
	var/obj/machinery/dq_breakpoint_probe/sandboxed = new_unmaterialized(/obj/machinery/dq_breakpoint_probe, T)
	TEST_ASSERT_NULL(dq_rule_binding_of(sandboxed), "an unmaterialized machine has no binding")
	sandboxed.take_damage(60, BRUTE, MELEE, FALSE)
	TEST_ASSERT(sandboxed.stat & BROKEN, "it still breaks")
	TEST_ASSERT_EQUAL(sandboxed.break_calls, 1, "once")
	qdel(sandboxed)
	qdel(listener)

/// Real machines through the base break: the flag, the signal, the fix.
/datum/unit_test/dq_machine_break_real_types

/datum/unit_test/dq_machine_break_real_types/Run()
	var/turf/T = test_floor()
	var/datum/dq_breakpoint_listener/listener = new
	for(var/path in list(/obj/machinery/computer, /obj/machinery/door/airlock, /obj/machinery/station_map, /obj/machinery/camera))
		var/obj/machinery/machine = allocate(path, T)
		listener.heard = 0
		listener.RegisterSignal(machine, COMSIG_MACHINERY_BROKEN, TYPE_PROC_REF(/datum/dq_breakpoint_listener, on_broken))
		TEST_ASSERT(machine.atom_break(), "[path]: breaks")
		TEST_ASSERT(machine.stat & BROKEN, "[path]: BROKEN is set")
		TEST_ASSERT_EQUAL(listener.heard, 1, "[path]: the signal is sent")
		TEST_ASSERT(machine.atom_fix(), "[path]: is fixed")
		TEST_ASSERT(!(machine.stat & BROKEN), "[path]: BROKEN is cleared")
		listener.UnregisterSignal(machine, COMSIG_MACHINERY_BROKEN)
		qdel(machine)
	qdel(listener)

// ---- Flavour text at each band ----

/datum/unit_test/dq_damage_flavour_bands

/datum/unit_test/dq_damage_flavour_bands/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/viewer = allocate(/mob/living/carbon/human, T)
	var/obj/structure/railing/railing = allocate(/obj/structure/railing, T)
	TEST_ASSERT(dq_rule_binding_of(railing), "railings subscribe their damage flavour")
	var/list/steps = list(1, 0.7, 0.45, 0.2, 0.6, 0.9, 0.1)
	var/list/bands = list(DAMAGE_BAND_NONE, DAMAGE_BAND_LIGHT, DAMAGE_BAND_MODERATE, DAMAGE_BAND_HEAVY, DAMAGE_BAND_LIGHT, DAMAGE_BAND_NONE, DAMAGE_BAND_HEAVY)
	for(var/i in 1 to length(steps))
		var/ratio = steps[i]
		var/band = bands[i]
		railing.update_integrity(ratio * railing.max_integrity)
		dq_rx_flush()
		dq_rules_settle(railing)
		TEST_ASSERT_EQUAL(railing.damage_band, band, "at [ratio] integrity the band is [band]")
		var/text = jointext(railing.examine(viewer), "\n")
		var/line = railing.damage_flavour_text(band)
		if(line)
			TEST_ASSERT(findtext(text, line), "at [ratio] examine shows the band's line")
		for(var/other in list(DAMAGE_BAND_LIGHT, DAMAGE_BAND_MODERATE, DAMAGE_BAND_HEAVY))
			if(other != band)
				TEST_ASSERT(!findtext(text, railing.damage_flavour_text(other)), "at [ratio] examine shows no other band's line")

	// Unbound atoms (walls, sandboxed objects) read the same declared levels.
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
	var/turf/T = test_floor()
	for(var/obj/item/stack/rods/R in T)
		qdel(R)
	var/obj/structure/railing/railing = allocate(/obj/structure/railing, T)
	railing.take_damage(railing.max_integrity * 2, BRUTE, MELEE, FALSE)
	TEST_ASSERT(QDELETED(railing), "the railing is destroyed")
	var/rods = 0
	for(var/obj/item/stack/rods/R in T)
		rods += R.get_amount()
		qdel(R)
	TEST_ASSERT_EQUAL(rods, 1, "its debris entry drops one rod")
