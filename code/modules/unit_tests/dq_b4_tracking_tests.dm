// B4: tracked base vars (G8) and reactive HUD / sight / canmove (no manual refresh).

/// A datum observing one change key of one source, counting deliveries.
/datum/dq_b4_key_probe
	var/hits = 0

/datum/dq_b4_key_probe/proc/on_key(list/keys)
	hits++

/// Observes `key` on `source` with a fresh probe (dropped with the test's allocations).
/datum/unit_test/proc/dq_b4_probe(datum/source, key)
	var/datum/dq_b4_key_probe/P = allocate(/datum/dq_b4_key_probe)
	observe(source, on_change(list(key), TYPE_PROC_REF(/datum/dq_b4_key_probe, on_key)), P, TYPE_PROC_REF(/datum/dq_b4_key_probe, on_key))
	return P

/// anchored, density and opacity are tracked base vars: a setter change publishes the var key once, a no-op publishes
/// nothing, and an admin edit goes through the setter.
/datum/unit_test/dq_b4_base_vars_publish

/datum/unit_test/dq_b4_base_vars_publish/Run()
	var/obj/structure/O = allocate(/obj/structure)
	O.set_anchored(FALSE)
	O.set_density(FALSE)
	O.set_opacity(FALSE)
	for(var/name in list("anchored", "density", "opacity"))
		var/datum/dq_b4_key_probe/P = dq_b4_probe(O, name)
		call(O, "set_[name]")(TRUE)
		call(O, "set_[name]")(TRUE)
		rx_drain()
		TEST_ASSERT_EQUAL(P.hits, 1, "set_[name]() of a change publishes [name] once (a repeat publishes nothing)")
		TEST_ASSERT(O.vv_edit_var(name, FALSE), "VV edits [name]")
		rx_drain()
		TEST_ASSERT_EQUAL(P.hits, 2, "an admin edit of [name] goes through its setter and publishes")
		TEST_ASSERT(!O.vars[name], "the edit wrote [name]")

/// The bridge: a machine's anchored and density setters still raise their declared field channel (no istype() in the
/// setter), and a plain object raises none.
/datum/unit_test/dq_b4_base_vars_bridge

/datum/unit_test/dq_b4_base_vars_bridge/Run()
	var/obj/machinery/M = allocate(/obj/machinery)
	var/datum/om/rec/rec = om_rec_of(M)
	var/datum/om/scheduler/sched = rec.sched
	M.om_listen |= CHANGE_MACHINE_ANCHORED | CHANGE_MACHINE_SETTINGS
	M.set_anchored(FALSE)
	sched.test_raises = list()
	M.set_anchored(TRUE)
	TEST_ASSERT_EQUAL(dq_sys_fields_count_raises(sched, M, CHANGE_MACHINE_ANCHORED), 1, "a machine's set_anchored raises CHANGE_MACHINE_ANCHORED")
	sched.test_raises = null
	var/list/plain = om_registry().fields_of(/obj/structure)
	TEST_ASSERT(!plain["anchored"] && !plain["density"], "a plain object's anchored and density raise no channel")

/// NOPOWER is the power capability's state (set_powered(), published as MACHINE_KEY_POWERED), BROKEN the integrity
/// state (atom_break() / atom_fix(), INTEGRITY_KEY_BROKEN), and use_power the tracked draw mode.
/datum/unit_test/dq_b4_machine_state_publishes

/datum/unit_test/dq_b4_machine_state_publishes/Run()
	var/obj/machinery/M = allocate(/obj/machinery)
	M.set_powered(TRUE)
	M.atom_fix()
	M.set_use_power(USE_POWER_IDLE)
	var/datum/dq_b4_key_probe/power = dq_b4_probe(M, MACHINE_KEY_POWERED)
	var/datum/dq_b4_key_probe/broken = dq_b4_probe(M, INTEGRITY_KEY_BROKEN)
	var/datum/dq_b4_key_probe/draw = dq_b4_probe(M, "use_power")
	TEST_ASSERT(M.set_powered(FALSE), "losing power is a change")
	TEST_ASSERT(!M.set_powered(FALSE), "losing it again is not")
	TEST_ASSERT(M.power_lost() && !M.operable(), "has_stat() and operable() read the power state")
	rx_drain()
	TEST_ASSERT_EQUAL(power.hits, 1, "set_powered() publishes MACHINE_KEY_POWERED once")
	M.atom_break()
	TEST_ASSERT(M.broken_now(), "atom_break() sets BROKEN")
	rx_drain()
	TEST_ASSERT_EQUAL(broken.hits, 1, "atom_break() publishes the integrity state")
	M.atom_fix()
	TEST_ASSERT(!M.broken_now(), "atom_fix() clears BROKEN")
	rx_drain()
	TEST_ASSERT_EQUAL(broken.hits, 2, "atom_fix() publishes it too")
	M.set_use_power(USE_POWER_ACTIVE)
	rx_drain()
	TEST_ASSERT_EQUAL(draw.hits, 1, "set_use_power() publishes the draw mode")

/// The generated reads reach the HUD reaction: every var key the human HUD pass reads (code/_generated/reads.dm,
/// reaction_reads()) runs the same on_change reaction as its declared keys.
/datum/unit_test/dq_b4_hud_generated_reads_merged

/datum/unit_test/dq_b4_hud_generated_reads_merged/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/rx_table/T = GLOB.rx_tables[H.type] || rx_table_build(H)
	TEST_ASSERT(T, "a human has a reactions table")
	for(var/key in list("nutrition", "fear", "tiredness", "blinded", "on_fire", "block_hud", "absorbed", "status_flags", \
		MOB_KEY_HUD_FLAGS, MOB_KEY_VIEW, "species", "mind"))
		var/found = FALSE
		for(var/datum/reaction/R in T.by_key[key])
			if(R.handler == TYPE_PROC_REF(/mob/living, life_hud_changed))
				found = TRUE
		TEST_ASSERT(found, "the human HUD reaction reads [key]")
	for(var/key in list("see_invisible_default", "seedarkness", MOB_KEY_VIEW))
		var/found = FALSE
		for(var/datum/reaction/R in T.by_key[key])
			if(R.handler == TYPE_PROC_REF(/mob/living, life_vision_changed))
				found = TRUE
		TEST_ASSERT(found, "the human sight reaction reads [key]")

/// Each HUD input changed through its setter (or its producer) runs the HUD pass with no manual call, once per drain.
/datum/unit_test/life_om/dq_b4_hud_follows_each_input

/datum/unit_test/life_om/dq_b4_hud_follows_each_input/run_life()
	var/mob/living/carbon/human/dq_test_hud_probe/H = allocate(/mob/living/carbon/human/dq_test_hud_probe)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.pretend_client = TRUE
	var/list/changes = list(
		"nutrition" = 0,
		"fear" = 40,
		"tiredness" = 30,
		"blinded" = TRUE,
		"on_fire" = TRUE,
		"block_hud" = TRUE,
		"vantag_pref" = VANTAG_KILL,
		"absorbed" = TRUE,
		"status_flags" = H.status_flags | FAKEDEATH,
	)
	for(var/name in changes)
		dq_b4_settle(H)
		H.hud_runs = 0
		if(name == "nutrition")
			H.adjust_nutrition(-50)
		else
			call(H, "set_[name]")(changes[name])
		TEST_ASSERT(life_test_rx_queued(H, TYPE_PROC_REF(/mob/living, life_hud_changed)), "changing [name] queues the HUD pass")
		rx_drain()
		TEST_ASSERT_EQUAL(H.hud_runs, 1, "changing [name] draws the HUD once, with no refresh call")
	// Producers that publish a key.
	dq_b4_settle(H)
	H.hud_runs = 0
	H.flag_hud_update(WANTED_HUD)
	rx_drain()
	TEST_ASSERT_EQUAL(H.hud_runs, 1, "flag_hud_update() draws the HUD")
	dq_b4_settle(H)
	H.hud_runs = 0
	H.recalculate_vis()
	rx_drain()
	TEST_ASSERT_EQUAL(H.hud_runs, 1, "a view change (MOB_KEY_VIEW) draws the HUD")
	H.pretend_client = FALSE

/// Waits out the HUD's at_most window and drains (twice: a pass held by the window runs in the first), so the next
/// change draws at once.
/// For the HUD probe it waits until a whole window passes with no pass (Life frames drain fear and tiredness).
/datum/unit_test/life_om/proc/dq_b4_settle(mob/living/L)
	var/mob/living/carbon/human/dq_test_hud_probe/P = istype(L, /mob/living/carbon/human/dq_test_hud_probe) ? L : null
	for(var/i in 1 to 8)
		rx_drain()
		var/runs = P?.hud_runs
		scheduler_advance(LIFE_PRESENT_MIN_INTERVAL / 10 + 0.1)
		rx_drain()
		if(!P || P.hud_runs == runs)
			break

/// Coalescing holds for generated reads: many inputs changed inside the at_most window draw once when it ends.
/datum/unit_test/life_om/dq_b4_hud_generated_reads_coalesce

/datum/unit_test/life_om/dq_b4_hud_generated_reads_coalesce/run_life()
	var/mob/living/carbon/human/dq_test_hud_probe/H = allocate(/mob/living/carbon/human/dq_test_hud_probe)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.pretend_client = TRUE
	dq_b4_settle(H)
	H.hud_runs = 0
	H.set_fear(10)
	rx_drain()
	TEST_ASSERT_EQUAL(H.hud_runs, 1, "the first change draws at the drain")
	for(var/i in 1 to 5)
		H.set_fear(10 + i)
		H.set_tiredness(i)
		H.adjust_nutrition(-1)
		H.flag_hud_update(HEALTH_HUD)
		rx_drain()
	TEST_ASSERT_EQUAL(H.hud_runs, 1, "changes inside the window are held")
	scheduler_advance(LIFE_PRESENT_MIN_INTERVAL / 10 + 0.1)
	rx_drain()
	TEST_ASSERT_EQUAL(H.hud_runs, 2, "and drawn once when it ends")
	H.pretend_client = FALSE

/// Sight follows its inputs on a clientless mob with no refresh call: see_invisible_default and seedarkness.
/datum/unit_test/life_om/dq_b4_vision_follows_inputs

/datum/unit_test/life_om/dq_b4_vision_follows_inputs/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	dq_b4_settle(H)
	H.set_see_invisible_default(SEE_INVISIBLE_LEVEL_TWO)
	dq_b4_settle(H)
	TEST_ASSERT_EQUAL(H.see_invisible, SEE_INVISIBLE_LEVEL_TWO, "raising see_invisible_default updates see_invisible")
	H.set_seedarkness(FALSE)
	dq_b4_settle(H)
	TEST_ASSERT_EQUAL(H.see_in_dark, 8, "turning seedarkness off gives full darksight")
	TEST_ASSERT_EQUAL(H.see_invisible, SEE_INVISIBLE_NOLIGHTING, "and no lighting plane")
	H.set_seedarkness(TRUE)
	dq_b4_settle(H)
	TEST_ASSERT(H.see_invisible != SEE_INVISIBLE_NOLIGHTING, "turning it back on restores it")

/// canmove follows resting through its setter: no update_canmove() call.
/datum/unit_test/life_om/dq_b4_canmove_follows_resting

/datum/unit_test/life_om/dq_b4_canmove_follows_resting/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.set_resting(FALSE)
	dq_b4_settle(H)
	TEST_ASSERT(!H.lying, "standing to begin with")
	H.set_resting(TRUE)
	TEST_ASSERT(life_test_rx_queued(H, TYPE_PROC_REF(/mob/living, life_canmove_changed)), "resting queues the canmove derivation")
	rx_drain()
	TEST_ASSERT(H.lying, "resting lays the mob down without an update_canmove() call")
	H.set_resting(FALSE)
	rx_drain()
	TEST_ASSERT(!H.lying, "and standing up raises it")
