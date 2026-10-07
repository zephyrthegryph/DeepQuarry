/**
 * Conversion pins: a generated snapshot of what a person can do with a type, recorded before a routine
 * conversion (legacy forms -> CAPABILITIES ops) and checked after it. Guide: doc/rewrite/snapshot_pins.md.
 *
 *   bash tools/dq_pin.sh /obj/machinery/foo [/obj/machinery/bar ...]   # before converting: record the pins
 *   ...convert...
 *   bash tools/dq_focused_test.sh dq_conversion_pin                     # after: what changed, row by row
 *   bash tools/dq_focused_test.sh --bless dq_conversion_pin             # accept the intended changes
 *
 * One file per type under code/modules/unit_tests/snapshots/pins/ (dq_snapshot_files.dm), so parallel
 * conversions never touch the same file and a pin-only change needs no recompile. The rows are keyed by
 * what a player sees, not by ids, so a faithful conversion leaves them unchanged:
 *
 *   <actor>|<held> menu: <label>                    an entry the interaction menu offers
 *   <actor>|<held> menu: <label> (refused: <why>)   an entry it shows greyed out, with the refusal
 *   <actor>|<held> click: <screentip>               what a plain click with that hand would do ("click: nothing")
 *   wires: <wire>, <wire>, ...                      the wires behind its panel (duds left out)
 *   keys: <key>, <key>, ...                         the op keys / interaction ids (expected to change on conversion)
 *
 * Actors: a human, a cyborg, an AI and a ghost, empty-handed; the human also holds each common tool and each
 * item a legacy interaction of the type asks for. A pin cannot see effects (what a click changes), timing, the
 * window's buttons or anything a sequence of steps reaches: hand-written pins still cover those.
 */
#define DQ_PIN_DIR "code/modules/unit_tests/snapshots/pins/"

/datum/unit_test/dq_conversion_pin
	var/list/capture_gravity_before

// Pinning visibility uses the shared lazy dview singleton. Warm it during fixture
// setup, before the runner snapshots globals; it remains the production cache.
/datum/unit_test/dq_conversion_pin/New()
	..()
	dview(0, test_floor())
	// Status lookup builds a persistent policy cache; retain the production cache
	// and initialize it before the runner records its globals.
	status_policies()
	// Rogue-zone console initialization uses this same persistent lazy controller.
	// Build it before the runner snapshots globals, without resetting its live state.
	if(!GLOB.rm_controller)
		GLOB.rm_controller = new /datum/controller/rogue()

/// The items the human holds besides an empty hand: the common tools (the welder is lit).
/proc/dq_pin_tools()
	return list(
		/obj/item/tool/screwdriver,
		/obj/item/tool/crowbar,
		/obj/item/tool/wrench,
		/obj/item/tool/wirecutters,
		/obj/item/multitool,
		/obj/item/weldingtool,
		/obj/item/stack/cable_coil,
		/obj/item/stack/material/steel,
		/obj/item/card/id,
	)

/datum/unit_test/dq_conversion_pin/proc/snapshot_name()
	return "pins"

/datum/unit_test/dq_conversion_pin/proc/snapshot_directory()
	return DQ_PIN_DIR

/datum/unit_test/dq_conversion_pin/Run()
	// Capturing hit reactions may take an act over. Restore this framework scratch
	// value after the sweep rather than leaving it for the next focused test.
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/list/bad = list()
	var/list/expected_by_type = dq_snapshot_read_dir(snapshot_directory(), bad)
	if(!length(expected_by_type) && !length(bad))
		return // no pins recorded
	var/turf/T = test_floor()
	capture_gravity_before = unit_test_gravity_snapshot()
	var/list/actors = list(
		"human" = allocate(/mob/living/carbon/human, T),
		"robot" = allocate(/mob/living/silicon/robot, T),
		"ai" = allocate(/mob/living/silicon/ai, T, null, null, null, TRUE),
		"ghost" = allocate(/mob/observer/dead, T),
	)
	// The rows read the actor's state (the toilet's Flush is offered silently to a mob that is not awake): the human stays awake for the whole
	// recording, however long it runs on the test floor's air.
	var/mob/living/carbon/human/pin_human = actors["human"]
	pin_human.enable_godmode()
	// A gravity generator going away switches its area's gravity off (as in play): the room gets its gravity back after the sweep, or every later
	// test's mobs drift (dq_p2_closet/drag_stuffs_a_person_into_an_open_closet).
	var/area/sweep_room = get_area(T)
	var/sweep_gravity = sweep_room.has_gravity
	defer_cleanup(src, PROC_REF(cleanup_pin_sweep), T, sweep_room, sweep_gravity)
	var/list/actual_by_type = list()
	// a turf is pinned in place of the tile beside the actors and turned back afterwards (a turf is never qdel'd)
	var/turf/beside = get_step(T, EAST)
	var/beside_type = beside?.type
	for(var/type in expected_by_type)
		// One seed per type, so a random initial state (the toilet's lid) is the same at every recording, whatever ran before it.
		rand_seed(1)
		var/list/baseline_atoms = dq_pin_fixture_atoms()
		var/list/baseline_allocated = allocated?.Copy() || list()
		var/target_gravity = sweep_room.has_gravity
		if(ispath(type, /turf))
			if(!beside)
				actual_by_type[type] = list("no tile to pin a turf on")
				continue
			var/turf/changed = beside.ChangeTurf(type)
			try
				actual_by_type[type] = dq_pin_lines(changed, T, actors)
			catch(var/exception/read_turf)
				actual_by_type[type] = list("runtime while reading it: [read_turf.name]")
			beside = changed.ChangeTurf(beside_type)
			TEST_ASSERT(dq_pin_cleanup_target(baseline_atoms, baseline_allocated, sweep_room, target_gravity), "turf capture left fixture products")
			continue
		var/atom/target = null
		try
			target = dq_snapshot_allocate(type, T)
		catch(var/exception/made)
			actual_by_type[type] = list("runtime while making it: [made.name]")
			continue
		if(QDELETED(target))
			actual_by_type[type] = list("deleted itself on creation")
			TEST_ASSERT(dq_pin_cleanup_target(baseline_atoms, baseline_allocated, sweep_room, target_gravity), "self-deleting capture left fixture products")
			continue
		try
			actual_by_type[type] = dq_pin_lines(target, T, actors)
		catch(var/exception/read)
			actual_by_type[type] = list("runtime while reading it: [read.name]")
		qdel(target)
		TEST_ASSERT(dq_pin_cleanup_target(baseline_atoms, baseline_allocated, sweep_room, target_gravity), "capture left fixture products")
	var/report = dq_snapshot_compare(snapshot_directory(), snapshot_name(), actual_by_type, expected_by_type, bad)
	TEST_ASSERT(isnull(report), report)

/// Preserve cleanup even when a declaration error aborts the sweep; the runner still reports the original runtime.
/datum/unit_test/dq_conversion_pin/proc/cleanup_pin_sweep(turf/T, area/sweep_room, sweep_gravity)
	own_turf_contents(T)
	// Dispose fixture-owned atoms before restoring gravity: a surviving generator's
	// destruction can switch its area's gravity off. The runner skips these deleted entries.
	for(var/datum/thing as anything in allocated?.Copy())
		if(!QDELETED(thing))
			qdel(thing)
	for(var/area/room as anything in capture_gravity_before)
		if(!QDELETED(room))
			room.gravitychange(capture_gravity_before[room])
	capture_gravity_before = null

/// Identity snapshot of this fixture block, including existing actor equipment and nested contents.
/// Do not materialize latent contents merely to identify already-existing fixture atoms.
/datum/unit_test/proc/dq_pin_fixture_atoms()
	var/list/found = list()
	for(var/turf/T in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
		found |= T.contents
	var/index = 1
	while(index <= length(found))
		var/atom/movable/thing = found[index++]
		if(!QDELETED(thing))
			found |= thing.contents
	return found

/// Dispose only what this capture created. Existing actors, held items and their contents survive.
/// Include teardown products and adjacent helper objects before the next capture starts.
/datum/unit_test/proc/dq_pin_cleanup_target(list/baseline_atoms, list/baseline_allocated, area/room, gravity)
	for(var/pass in 1 to 4)
		var/list/products = (allocated?.Copy() || list()) - baseline_allocated
		products |= dq_pin_fixture_atoms() - baseline_atoms
		if(!length(products))
			break
		for(var/datum/thing as anything in products)
			if(!QDELETED(thing))
				qdel(thing)
	if(room && room.has_gravity != gravity)
		room.gravitychange(gravity)
	return !length(dq_pin_fixture_atoms() - baseline_atoms)

/// The pin rows of one target (see the file comment), sorted so the file diffs cleanly.
/datum/unit_test/proc/dq_pin_lines(atom/target, turf/T, list/actors)
	. = list()
	// As the i7 snapshots do: a freshly made machine can read unpowered until the power system's next step.
	if(ismachinery(target))
		var/obj/machinery/M = target
		M.set_grid_power(TRUE)
		M.set_broken_condition(FALSE)
	var/list/held_types = dq_pin_tools()
	for(var/datum/interaction/interaction as anything in interaction_candidates(target))
		if(!interaction.held_type)
			continue
		var/path = islist(interaction.held_type) ? interaction.held_type[1] : interaction.held_type
		if(ispath(path, /obj/item) && !ispath(path, /obj/item/grab))
			held_types |= path
	// ...and each item an op of the type binds (item(T), stack(T)), so a converted type is probed with what its legacy interactions asked for
	var/datum/op_index/probe_index = op_index_of_table(table_of(target))
	for(var/key in probe_index?.by_key)
		var/datum/op_plan/plan = probe_index.by_key[key]
		for(var/datum/entry/part/bind/binding as anything in plan?.bindings)
			if(binding.bind_kind != BIND_ITEM && binding.bind_kind != BIND_STACK)
				continue
			var/bound = binding.args["type"]
			// a holder is made around a mob (its constructor param), so a bare one is not a probe
			if(ispath(bound, /obj/item) && !ispath(bound, /obj/item/grab) && !ispath(bound, /obj/item/holder))
				held_types |= bound
	var/list/combinations = list(list("human", null), list("robot", null), list("ai", null), list("ghost", null))
	for(var/path in held_types)
		combinations += list(list("human", path))
	for(var/list/combination as anything in combinations)
		var/mob/actor = actors[combination[1]]
		var/held_path = combination[2]
		var/held_name = held_path ? "[held_path]" : "none"
		var/obj/item/held = null
		if(held_path)
			held = dq_snapshot_allocate(held_path, T)
			if(QDELETED(held))
				. += "[combination[1]]|[held_name] deleted itself on creation"
				continue
			var/obj/item/weldingtool/welder = held.get_welder()
			welder?.set_welding(TRUE)
		var/list/menu = list()
		var/prefix = "[combination[1]]|[held_name] menu: "
		// The engine's ops (op_menu) and, while the type is legacy, its interactions (what the Menu window lists).
		for(var/list/row as anything in op_menu(actor, target, held))
			var/label = "[row["label"]]"
			menu |= row["enabled"] ? "[prefix][label]" : "[prefix][label] (refused: [row["reason"]])"
		var/datum/interaction_resolution/resolution = interactions_for(actor, target, held)
		for(var/datum/interaction/interaction as anything in resolution.available)
			menu |= "[prefix][interaction.display_name(actor, target)]"
		for(var/datum/interaction/interaction as anything in resolution.blocked)
			menu |= "[prefix][interaction.display_name(actor, target)] (refused: [resolution.blocked[interaction]])"
		sortTim(menu, GLOBAL_PROC_REF(cmp_text_asc))
		. += menu
		. += "[combination[1]]|[held_name] click: [screentip_for(actor, target, held) || "nothing"]"
		if(held)
			qdel(held)
	var/list/wires = list()
	for(var/wire in wires_all(target))
		if(!wire_is_dud(wire))
			wires += "[wire]"
	if(length(wires))
		sortTim(wires, GLOBAL_PROC_REF(cmp_text_asc))
		. += "wires: [jointext(wires, ", ")]"
	var/list/keys = list()
	var/datum/op_index/index = op_index_of_table(table_of(target))
	for(var/key in index?.by_key)
		// A topic link (an href in a window or a chat line) is not something a click reaches: the dq_topic_* tests pin those, and listing them would add the
		// same View Variables and stat panel keys to every atom.
		var/datum/op_plan/listed = index.by_key[key]
		if(listed?.topic_key)
			continue
		keys += "[key]"
	for(var/datum/interaction/interaction as anything in interaction_candidates(target))
		keys |= dq_snapshot_id(interaction.id)
	if(length(keys))
		sortTim(keys, GLOBAL_PROC_REF(cmp_text_asc))
		. += "keys: [jointext(keys, ", ")]"

#undef DQ_PIN_DIR

/// Per-target capture cleanup must not erase the actors or the current target's legitimate helpers.
/datum/unit_test/dq_conversion_pin_fixture_isolation/New()
	..()
	dview(0, test_floor())

/datum/unit_test/dq_conversion_pin_fixture_isolation/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.enable_godmode()
	var/obj/item/pen/sentinel = allocate(/obj/item/pen, T)
	var/obj/item/tool/wrench/held = allocate(/obj/item/tool/wrench, H)
	TEST_ASSERT(H.put_in_active_hand(held), "the baseline tool is actually held")
	var/list/actors = list("human" = H, "robot" = allocate(/mob/living/silicon/robot, T), "ai" = allocate(/mob/living/silicon/ai, T, null, null, null, TRUE), "ghost" = allocate(/mob/observer/dead, T))
	var/list/baseline_atoms = dq_pin_fixture_atoms()
	var/list/baseline_allocated = allocated.Copy()
	var/area/room = get_area(T)
	var/gravity = room.has_gravity
	var/obj/machinery/mineral/processing_unit_console/target = dq_snapshot_allocate(/obj/machinery/mineral/processing_unit_console, T)
	var/obj/machinery/mineral/processing_unit/helper = locate(/obj/machinery/mineral/processing_unit) in T
	TEST_ASSERT(!QDELETED(target) && !QDELETED(helper), "the actual console fixture creates its processing helper")
	var/obj/item/pen/adjacent = new /obj/item/pen(get_step(T, EAST))
	own(adjacent)
	var/list/rows = dq_pin_lines(target, T, actors)
	TEST_ASSERT(length(rows), "the actual target is captured before disposal")
	TEST_ASSERT(!QDELETED(helper), "the current target's helper survives the whole capture")
	TEST_ASSERT(dq_pin_cleanup_target(baseline_atoms, baseline_allocated, room, gravity), "capture cleanup removes new products")
	TEST_ASSERT(QDELETED(target) && QDELETED(helper) && QDELETED(adjacent), "the target and both on-tile and adjacent helpers are disposed")
	TEST_ASSERT(!QDELETED(H) && !QDELETED(sentinel) && !QDELETED(held), "baseline actor, sentinel and held item survive")
	TEST_ASSERT(held in H.get_all_held_items(), "cleanup preserves actual hand bookkeeping")
	var/mob/living/silicon/ai/empty = dq_snapshot_allocate(/mob/living/silicon/ai, T)
	TEST_ASSERT(QDELETED(empty), "a bare AI target really deletes itself")
	var/obj/structure/AIcore/deactivated/core = locate(/obj/structure/AIcore/deactivated) in T
	TEST_ASSERT_NOTNULL(core, "the deleted AI really left an inactive core")
	own(core) // emergency test teardown also owns this initializer product
	TEST_ASSERT(dq_pin_cleanup_target(baseline_atoms, baseline_allocated, room, gravity), "the self-deleting target follows the same cleanup path")
	TEST_ASSERT(QDELETED(core), "the orphan core cannot add Climb to subsequent captures")
	TEST_ASSERT(!QDELETED(sentinel) && (held in H.get_all_held_items()), "a second cleanup still preserves the baseline fixture")

/datum/unit_test/dq_conversion_pin_fixture_gravity/Run()
	var/turf/T = test_floor()
	var/area/room = get_area(T)
	var/gravity = room.has_gravity
	defer_cleanup(room, TYPE_PROC_REF(/area, gravitychange), gravity)
	var/list/baseline_atoms = dq_pin_fixture_atoms()
	var/list/baseline_allocated = allocated?.Copy() || list()
	room.gravitychange(!gravity)
	TEST_ASSERT_EQUAL(room.has_gravity, !gravity, "the fixture actually changes room gravity")
	TEST_ASSERT(dq_pin_cleanup_target(baseline_atoms, baseline_allocated, room, gravity), "target cleanup completes")
	TEST_ASSERT_EQUAL(room.has_gravity, gravity, "gravity is restored before the next capture")
