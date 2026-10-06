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

/datum/unit_test/dq_conversion_pin/Run()
	var/list/bad = list()
	var/list/expected_by_type = dq_snapshot_read_dir(DQ_PIN_DIR, bad)
	if(!length(expected_by_type) && !length(bad))
		return // no pins recorded
	var/turf/T = test_floor()
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
	var/list/actual_by_type = list()
	// a turf is pinned in place of the tile beside the actors and turned back afterwards (a turf is never qdel'd)
	var/turf/beside = get_step(T, EAST)
	var/beside_type = beside?.type
	for(var/type in expected_by_type)
		// One seed per type, so a random initial state (the toilet's lid) is the same at every recording, whatever ran before it.
		rand_seed(1)
		if(ispath(type, /turf))
			if(!beside)
				actual_by_type[type] = list("no tile to pin a turf on")
				continue
			var/turf/changed = beside.ChangeTurf(type)
			actual_by_type[type] = dq_pin_lines(changed, T, actors)
			beside = changed.ChangeTurf(beside_type)
			continue
		var/atom/target = dq_snapshot_allocate(type, T)
		if(QDELETED(target))
			actual_by_type[type] = list("deleted itself on creation")
			continue
		actual_by_type[type] = dq_pin_lines(target, T, actors)
		qdel(target)
	if(sweep_room.has_gravity != sweep_gravity)
		sweep_room.gravitychange(sweep_gravity)
	own_turf_contents(T)
	var/report = dq_snapshot_compare(DQ_PIN_DIR, "pins", actual_by_type, expected_by_type, bad)
	TEST_ASSERT(isnull(report), report)

/// The pin rows of one target (see the file comment), sorted so the file diffs cleanly.
/datum/unit_test/proc/dq_pin_lines(atom/target, turf/T, list/actors)
	. = list()
	// As the i7 snapshots do: a freshly made machine can read unpowered until the power system's next step.
	if(ismachinery(target))
		var/obj/machinery/M = target
		M.stat_remove(NOPOWER|BROKEN)
	var/list/held_types = dq_pin_tools()
	for(var/datum/interaction/interaction as anything in interaction_candidates(target))
		if(!interaction.held_type)
			continue
		var/path = islist(interaction.held_type) ? interaction.held_type[1] : interaction.held_type
		if(ispath(path, /obj/item) && !ispath(path, /obj/item/grab))
			held_types |= path
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
		keys += "[key]"
	for(var/datum/interaction/interaction as anything in interaction_candidates(target))
		keys |= dq_snapshot_id(interaction.id)
	if(length(keys))
		sortTim(keys, GLOBAL_PROC_REF(cmp_text_asc))
		. += "keys: [jointext(keys, ", ")]"

#undef DQ_PIN_DIR
