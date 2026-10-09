// The domain snapshot harness (doc/rewrite/snapshot_pins.md, "The i7 interaction snapshots"): the resolved interaction lists of a type per actor and held item.
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
		M.set_grid_power(TRUE)
		M.set_broken_condition(FALSE)
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
	if(ispath(type, /obj/structure/blob/core))
		// A core rolls its blob type from the RNG (the random_* cores by difficulty, the rest of the plain ones from every type), so its
		// colour followed whatever the RNG had drawn: the snapshot subject is placed without an overmind and given one of a fixed type
		// (its own, when the core names one).
		var/obj/structure/blob/core/core = allocate(type, T, null, 2, TRUE)
		if(!QDELETED(core))
			core.desired_blob_type ||= /datum/blob_type/classic
			core.create_overmind(null, TRUE)
		return core
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

