// Legacy entries (roadmap I7): converted attackby, attack_hand, attack_self,
// click_alt and MouseDrop_T handlers run from their old entry procs, in the
// override chain's order. Also the snapshot harness the domain snapshots use.

// ---- Fixtures ----

/// A probe whose parent and child types each declare entry interactions.
/obj/dq_entry_probe
	name = "entry probe"
	var/list/done
	var/allow_second = TRUE
	var/gate_stops = FALSE
	var/gate_calls = 0

/obj/dq_entry_probe/declare_interactions(list/into)
	into += list(
		/datum/interaction/dq_entry/parent_item,
		/datum/interaction/dq_entry/parent_hand,
	)
	..()

/obj/dq_entry_probe/hand_gate(mob/user)
	gate_calls++
	if(gate_stops)
		return TRUE
	return ..()

/obj/dq_entry_probe/child

/obj/dq_entry_probe/child/declare_interactions(list/into)
	into += list(
		/datum/interaction/dq_entry/child_crowbar,
		/datum/interaction/dq_entry/child_declines,
		/datum/interaction/dq_entry/child_blocked,
		/datum/interaction/dq_entry/child_ungated_hand,
		/datum/interaction/dq_entry/child_alt,
		/datum/interaction/dq_entry/child_drag,
	)
	..()

/obj/dq_entry_probe/proc/note_entry(mob/actor, atom/held, datum/interaction/interaction)
	LAZYADD(done, interaction.id)
	return TRUE

/obj/dq_entry_probe/proc/decline_entry(mob/actor, atom/held, datum/interaction/interaction)
	LAZYADD(done, interaction.id)
	return FALSE

/obj/dq_entry_probe/proc/second_allowed(mob/actor, atom/target, obj/item/held)
	return allow_second ? TRUE : "the probe says no"

/obj/item/dq_entry_probe_item
	name = "entry probe item"
	var/list/done

/obj/item/dq_entry_probe_item/declare_interactions(list/into)
	into += list(/datum/interaction/dq_entry/self_use)
	..()

/obj/item/dq_entry_probe_item/proc/note_self(mob/actor, atom/held, datum/interaction/interaction)
	LAZYADD(done, interaction.id)
	return TRUE

/datum/interaction/dq_entry
	requires = list(REQ_INTERACTION_REACH)
	effect = /obj/dq_entry_probe/proc/note_entry

/datum/interaction/dq_entry/parent_item
	id = "dq_entry_parent_item"
	name = "Parent item"
	entry = INTERACTION_ENTRY_ITEM
	held_type = /obj/item

/datum/interaction/dq_entry/parent_hand
	id = "dq_entry_parent_hand"
	name = "Parent hand"
	entry = INTERACTION_ENTRY_HAND

/datum/interaction/dq_entry/child_crowbar
	id = "dq_entry_child_crowbar"
	name = "Child crowbar"
	entry = INTERACTION_ENTRY_ITEM
	held_type = /obj/item/tool/crowbar

/datum/interaction/dq_entry/child_declines
	id = "dq_entry_child_declines"
	name = "Child declines"
	entry = INTERACTION_ENTRY_ITEM
	held_type = /obj/item/tool/wrench
	effect = /obj/dq_entry_probe/proc/decline_entry

/datum/interaction/dq_entry/child_blocked
	id = "dq_entry_child_blocked"
	name = "Child blocked"
	entry = INTERACTION_ENTRY_ITEM
	held_type = /obj/item/tool/screwdriver
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/dq_entry_probe/proc/second_allowed, null))

/datum/interaction/dq_entry/child_ungated_hand
	id = "dq_entry_child_ungated_hand"
	name = "Child ungated hand"
	entry = INTERACTION_ENTRY_HAND
	behind_gate = FALSE
	offered_when = list(REQ_ON(PRED_TARGET, /obj/dq_entry_probe/proc/second_allowed, null))

/datum/interaction/dq_entry/child_alt
	id = "dq_entry_child_alt"
	name = "Child alt"
	entry = INTERACTION_ENTRY_ALT
	default_action = INPUT_ACTION_ALTERNATE

/datum/interaction/dq_entry/child_drag
	id = "dq_entry_child_drag"
	name = "Child drag"
	entry = INTERACTION_ENTRY_DRAG
	held_type = /obj/item/tool/wrench

/datum/interaction/dq_entry/self_use
	id = "dq_entry_self_use"
	name = "Self use"
	entry = INTERACTION_ENTRY_SELF
	requires = null
	effect = /obj/item/dq_entry_probe_item/proc/note_self

// ---- Tests ----

/// attackby: the child's interactions come first, a declining effect falls through, a blocked one stops.
/datum/unit_test/dq_interaction_entry_item

/datum/unit_test/dq_interaction_entry_item/Run()
	var/turf/T = test_floor()
	var/obj/dq_entry_probe/child/probe = allocate(/obj/dq_entry_probe/child, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/obj/item/dq_entry_probe_item/other = allocate(/obj/item/dq_entry_probe_item, T)

	TEST_ASSERT(probe.attackby(crowbar, H), "a crowbar is used up")
	TEST_ASSERT_EQUAL(jointext(probe.done || list(), ","), "dq_entry_child_crowbar", "the child's crowbar handler answers, not the parent's any-item one")
	LAZYCLEARLIST(probe.done)
	probe.attackby(wrench, H)
	TEST_ASSERT_EQUAL(jointext(probe.done || list(), ","), "dq_entry_child_declines,dq_entry_parent_item", "a declining effect falls through to the parent, as ..() did")
	LAZYCLEARLIST(probe.done)
	probe.allow_second = FALSE
	TEST_ASSERT(probe.attackby(screwdriver, H), "a blocked handler still uses the input")
	TEST_ASSERT_EQUAL(length(probe.done), 0, "a blocked handler stops there, as an early return did")
	probe.attackby(other, H)
	TEST_ASSERT_EQUAL(jointext(probe.done || list(), ","), "dq_entry_parent_item", "anything else reaches the parent's handler")
	var/datum/interaction_resolution/resolution = interactions_for(H, probe, crowbar)
	TEST_ASSERT_NULL(try_interaction(H, probe, crowbar, INPUT_ACTION_USE, null, TRUE), "the resolver's Use leaves entries to their entry procs")
	TEST_ASSERT(INTERACTION(/datum/interaction/dq_entry/child_crowbar) in resolution.available, "but they are listed")

/// attack_hand: the gate runs below the first gated handler; an ungated one runs before it.
/datum/unit_test/dq_interaction_entry_hand

/datum/unit_test/dq_interaction_entry_hand/Run()
	var/turf/T = test_floor()
	var/obj/dq_entry_probe/child/probe = allocate(/obj/dq_entry_probe/child, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	probe.gate_stops = TRUE
	TEST_ASSERT(probe.attack_hand(H), "the ungated handler answers")
	TEST_ASSERT_EQUAL(jointext(probe.done || list(), ","), "dq_entry_child_ungated_hand", "without the gate")
	TEST_ASSERT_EQUAL(probe.gate_calls, 0, "the gate didn't run")
	LAZYCLEARLIST(probe.done)
	probe.allow_second = FALSE
	TEST_ASSERT(probe.attack_hand(H), "the gate stopped the touch")
	TEST_ASSERT_EQUAL(length(probe.done), 0, "so the parent's gated handler didn't run")
	TEST_ASSERT_EQUAL(probe.gate_calls, 1, "the gate ran once")
	probe.gate_stops = FALSE
	TEST_ASSERT(probe.attack_hand(H), "the parent's handler answers")
	TEST_ASSERT_EQUAL(jointext(probe.done || list(), ","), "dq_entry_parent_hand", "behind the gate")

	var/obj/dq_entry_probe/far = allocate(/obj/dq_entry_probe, locate(T.x + 3, T.y, T.z))
	var/datum/interaction/parent_hand = INTERACTION(/datum/interaction/dq_entry/parent_hand)
	TEST_ASSERT_EQUAL(parent_hand.why_not(H, far, null), "too far away", "out of reach in the Menu")
	GLOB.interaction_entry_actors[H] = 1
	TEST_ASSERT_NULL(parent_hand.why_not(H, far, null), "the entry's caller decided reach (telekinesis)")
	GLOB.interaction_entry_actors -= H

/// attack_self, click_alt and MouseDrop_T reach their interactions.
/datum/unit_test/dq_interaction_entry_other

/datum/unit_test/dq_interaction_entry_other/Run()
	var/turf/T = test_floor()
	var/obj/dq_entry_probe/child/probe = allocate(/obj/dq_entry_probe/child, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/dq_entry_probe_item/item = allocate(/obj/item/dq_entry_probe_item, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)

	TEST_ASSERT(item.attack_self(H), "attack_self is answered")
	TEST_ASSERT_EQUAL(jointext(item.done || list(), ","), "dq_entry_self_use", "by the self-use interaction")
	TEST_ASSERT_EQUAL(probe.click_alt(H), CLICK_ACTION_SUCCESS, "click_alt is answered")
	probe.MouseDrop_T(wrench, H)
	TEST_ASSERT_EQUAL(jointext(probe.done || list(), ","), "dq_entry_child_alt,dq_entry_child_drag", "the alt and drag interactions ran")

// ---- Snapshot harness ----

/**
 * The snapshot lines for `target`: the resolved lists for a human with nothing
 * in hand and holding one of each item its interactions name, a cyborg, the AI
 * and a ghost. Format: "type|actor|held => available|blocked:reason,...".
 */
/datum/unit_test/proc/dq_snapshot_lines(atom/target, turf/T, list/actors)
	. = list()
	// Newly-allocated machinery can briefly read as unpowered until the power
	// subsystem's next tick, which raced this snapshot in a full-suite run
	// (never in a focused run, which skips that wait): clear NOPOWER/BROKEN so
	// the recorded snapshot reflects the interaction wiring, not power timing.
	if(ismachinery(target))
		var/obj/machinery/M = target
		M.stat_remove(NOPOWER|BROKEN)
	var/list/held_types = list()
	for(var/datum/interaction/interaction as anything in interaction_candidates(target))
		if(interaction.held_type)
			var/path = islist(interaction.held_type) ? interaction.held_type[1] : interaction.held_type
			// Only sample plain items: a standalone /obj/item/grab or /mob (drag targets
			// for machine_drag interactions) isn't safe to allocate on a bare turf, so
			// those combinations are skipped; the id still shows up via the no-item case.
			if(ispath(path, /obj/item) && !ispath(path, /obj/item/grab))
				held_types |= path
	var/list/combinations = list(list("human", null), list("robot", null), list("ai", null), list("ghost", null))
	for(var/path in held_types)
		combinations += list(list("human", path))
	for(var/list/combination as anything in combinations)
		var/atom/held = combination[2] ? dq_snapshot_allocate(combination[2], T) : null
		// Some held tools only exist inside a cyborg (a gripper deletes itself anywhere else,
		// and a link to a dying entity is refused): sample those inside the snapshot's robot.
		if(held && QDELETED(held) && actors["robot"])
			held = allocate(combination[2], actors["robot"])
		if(held && QDELETED(held))
			. += "[target.type]|[combination[1]]|[combination[2]] => deleted itself on creation"
			continue
		var/datum/interaction_resolution/resolution = interactions_for(actors[combination[1]], target, held)
		. += "[target.type]|[combination[1]]|[combination[2] || "none"] => [dq_resolution_text(resolution)]"
		if(held)
			qdel(held)

/**
 * Allocates a snapshot subject with what it needs to exist: some types delete themselves while
 * initializing when a partner is missing, and nothing may link to a dying entity (ownership.md
 * 4.1), so the snapshot builds the partner first rather than sampling a deleted object.
 */
/datum/unit_test/proc/dq_snapshot_allocate(type, turf/T)
	if(ispath(type, /obj/machinery/mineral/processing_unit_console))
		allocate(/obj/machinery/mineral/processing_unit, T) // the console finds its machine in range
		return allocate(type, T)
	if(ispath(type, /obj/machinery/shieldwall))
		var/obj/machinery/shieldwallgen/A = allocate(/obj/machinery/shieldwallgen, T)
		var/obj/machinery/shieldwallgen/B = allocate(/obj/machinery/shieldwallgen, T)
		A.set_active(1) // a wall stands only between two running generators
		B.set_active(1)
		return allocate(type, T, A, B)
	if(ispath(type, /obj/item/reagent_containers/food/snacks/grown))
		var/list/seeds = SSplants.seeds
		return allocate(type, T, length(seeds) ? seeds[1] : null) // produce needs a plant name
	return allocate(type, T)

/// Abstract: one domain's recorded snapshot. A subtype sets `snapshot_dir` (one rows file per type, dq_snapshot_files.dm),
/// or, the older form, lists `snapshot_types` and `expected` inline.
/datum/unit_test/dq_interaction_domain_snapshot
	abstract_type = /datum/unit_test/dq_interaction_domain_snapshot
	var/list/snapshot_types
	var/list/expected
	/// The directory of per-type rows files (code/modules/unit_tests/snapshots/<name>/); the types are its files.
	var/snapshot_dir
	/// type => its recorded rows (filled from snapshot_dir by load_snapshot()).
	var/list/expected_by_type
	/// Files under snapshot_dir that name no type.
	var/list/bad_snapshot_files

/// Reads snapshot_dir into snapshot_types, expected and expected_by_type (once).
/datum/unit_test/dq_interaction_domain_snapshot/proc/load_snapshot()
	if(!snapshot_dir || expected_by_type)
		return
	bad_snapshot_files = list()
	expected_by_type = dq_snapshot_read_dir(snapshot_dir, bad_snapshot_files)
	snapshot_types = list()
	expected = list()
	for(var/type in expected_by_type)
		snapshot_types += type
		expected += expected_by_type[type]

/datum/unit_test/dq_interaction_domain_snapshot/Run()
	load_snapshot()
	var/turf/T = test_floor()
	var/list/actors = list(
		"human" = allocate(/mob/living/carbon/human, T),
		"robot" = allocate(/mob/living/silicon/robot, T),
		"ai" = allocate(/mob/living/silicon/ai, T, null, null, null, TRUE),
		"ghost" = allocate(/mob/observer/dead, T),
	)
	// A gravity generator going away switches its area's gravity off (as in play): the room gets its gravity back after the sweep, or every later
	// test's mobs drift (dq_p2_closet/drag_stuffs_a_person_into_an_open_closet).
	var/area/sweep_room = get_area(T)
	var/sweep_gravity = sweep_room.has_gravity
	var/list/actual_by_type = list()
	var/list/actual = list()
	for(var/type in snapshot_types)
		var/atom/target = dq_snapshot_allocate(type, T)
		// A type that replaces itself while initializing (the arcade base picks a random
		// cabinet), or deletes itself (a lattice off open space), is gone before anyone can interact
		// with it; nothing may link to it.
		if(QDELETED(target))
			actual_by_type[type] = list("[type] => deleted itself on creation")
			actual += actual_by_type[type]
			continue
		actual_by_type[type] = dq_snapshot_lines(target, T, actors)
		actual += actual_by_type[type]
		qdel(target)
	if(sweep_room.has_gravity != sweep_gravity)
		sweep_room.gravitychange(sweep_gravity)
	if(snapshot_dir)
		var/snap_name = copytext("[type]", length("[/datum/unit_test/dq_interaction_domain_snapshot]") + 2)
		var/report = dq_snapshot_compare(snapshot_dir, snap_name, actual_by_type, expected_by_type, bad_snapshot_files)
		TEST_ASSERT(isnull(report), report)
		return
	// The inline form: on a mismatch, write the actual lines out so the snapshot can be reviewed
	// and regenerated: data/test-snapshots/<test type>.txt.
	if(length(actual ^ expected))
		var/file_name = "data/test-snapshots/[replacetext("[type]", "/", "_")].txt"
		fdel(file_name)
		text2file(jointext(actual, "\n"), file_name)
	// Every mismatch is listed in one failure (and the whole current snapshot is in the file above), so one run is enough to regenerate the rows.
	var/list/mismatches = list()
	for(var/line in actual)
		if(!(line in expected))
			mismatches += "new or changed snapshot: [line]"
	for(var/line in expected)
		if(!(line in actual))
			mismatches += "missing snapshot: [line]"
	var/report = "[length(mismatches)] snapshot rows differ (the current rows are in data/test-snapshots):"
	for(var/row in mismatches)
		report += "\n[row]"
	TEST_ASSERT(!length(mismatches), report)

/// Every entry interaction id recorded in a domain snapshot: those need no dedicated test.
/proc/dq_snapshot_covered_ids()
	var/static/list/covered
	if(covered)
		return covered
	covered = list()
	for(var/datum/unit_test/dq_interaction_domain_snapshot/path as anything in subtypesof(/datum/unit_test/dq_interaction_domain_snapshot))
		var/datum/unit_test/dq_interaction_domain_snapshot/test = new path
		test.load_snapshot()
		for(var/line in test.expected)
			var/arrow = findtext(line, " => ")
			if(!arrow)
				continue
			for(var/part in splittext(replacetext(copytext(line, arrow + 4), "|", ","), ","))
				var/colon = findtext(part, ":")
				covered[colon ? copytext(part, 1, colon) : part] = TRUE
	return covered
