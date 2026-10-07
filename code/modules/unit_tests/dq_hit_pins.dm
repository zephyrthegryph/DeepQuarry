/**
 * Hit pins: a generated snapshot of what a thing does when it is hit or emagged, recorded before a hit-reaction or emag
 * conversion (DAMAGE_REACTION, DAMAGE_REACTION_AFTER, DECLARE_EMAG -> hit hooks, emag ops) and checked after it.
 *
 *   bash tools/dq_pin.sh --hit /obj/item/foo [...]                   # before converting: record the pins
 *   ...convert...
 *   bash tools/dq_focused_test.sh dq_hit_pin                          # after: what changed, row by row
 *
 * One file per type under code/modules/unit_tests/snapshots/hit_pins/ (dq_snapshot_files.dm). Each type is made on the
 * test floor, hit through its public entry (emp_act, ex_act, bullet_act, blob_act, hitby) and, for an emag, clicked
 * with a cryptographic sequencer; the rows are what changed:
 *
 *   <trigger> | <var>: <old> -> <new>      a var of the target (numbers, text, paths; a datum is its type; a list its length)
 *   <trigger> | deleted                    the target was deleted
 *   <trigger> | turf: +<type> xN / -<type> xN   what appeared on, or left, the target's tile
 *   <trigger> | nothing                    no visible change
 *
 * Random effects are reseeded per trigger. A pin sees the state at the end of the call and one drain later, not a
 * timer that runs seconds on: a hand-written test covers those.
 */
#define DQ_HIT_PIN_DIR "code/modules/unit_tests/snapshots/hit_pins/"

/datum/unit_test/dq_hit_pin

/// Vars that carry no behaviour (identity, engine bookkeeping) or change on their own.
/proc/dq_hit_skip_vars()
	var/static/list/skip = list(
		"vars", "type", "parent_type", "contents", "overlays", "underlays", "verbs", "vis_contents", "vis_locs", "filters", "appearance",
		"tag", "x", "y", "z", "loc", "locs", "bound_x", "bound_y", "bound_width", "bound_height", "step_x", "step_y", "weak_reference",
		"datum_flags", "gc_destroyed", "comp_lookup", "signal_procs", "status_traits", "_listen_lookup", "active_timers", "cooldowns",
		"light", "light_sources", "x_pos", "y_pos", "z_pos", "ckey", "key", "mind", "client", "last_move", "last_move_time", "pixloc",
		"om_hid", "own_key_text", "last_damage_flag",
	)
	return skip

/// One var's value as a pin row writes it: stable between runs. A number near the clock is written relative to it.
/proc/dq_hit_value(value)
	if(isnull(value))
		return "null"
	if(isnum(value))
		if(world.time > 1000 && value >= world.time - 5 && value <= world.time + 18000 && value == round(value))
			return "<now+[value - world.time]>"
		return "[round(value, 0.0001)]"
	if(istext(value))
		return "'[value]'"
	if(ispath(value))
		return "[value]"
	if(islist(value))
		var/list/L = value
		return "list([length(L)])"
	if(isdatum(value))
		var/datum/D = value
		return QDELETED(D) ? "deleted [D.type]" : "[D.type]"
	return "[value]"

/// The pinned state of `target`: var name -> written value.
/proc/dq_hit_state(atom/target)
	. = list()
	var/list/skip = dq_hit_skip_vars()
	for(var/name in target.vars)
		if(name in skip)
			continue
		var/value = target.vars[name]
		.[name] = dq_hit_value(value)

/// The things standing on a tile besides `target`: type -> count.
/proc/dq_hit_turf_rows(turf/T, atom/target)
	var/list/counts = list()
	for(var/atom/movable/AM as anything in contents_of(T))
		if(AM == target || istype(AM, /obj/effect/landmark) || ismob(AM))
			continue
		// the harness's own props (the projectile, the card, the thrown crowbar, the blob that hits)
		if(istype(AM, /obj/item/projectile) || istype(AM, /obj/item/card/emag) || istype(AM, /obj/item/tool/crowbar) || istype(AM, /obj/structure/blob))
			continue
		counts["[AM.type]"] = (counts["[AM.type]"] || 0) + 1
	return counts

/// One trigger delivered through the thing's public entry.
/datum/unit_test/proc/dq_hit_apply(atom/target, trigger, mob/living/carbon/human/actor)
	switch(trigger)
		if("emp 1")
			target.emp_act(1)
		if("emp 2")
			target.emp_act(2)
		if("explosion 1")
			target.ex_act(1)
		if("explosion 2")
			target.ex_act(2)
		if("explosion 3")
			target.ex_act(3)
		if("projectile")
			var/obj/item/projectile/P = allocate(/obj/item/projectile)
			P.injury_kind = INJURY_PIERCE
			P.injury_kinds = null
			P.damage = 20
			P.nodamage = FALSE
			P.emp_on_hit = FALSE
			target.bullet_act(P, BP_TORSO)
		if("blob")
			var/obj/structure/blob/B = allocate(/obj/structure/blob)
			target.blob_act(B)
		if("thrown")
			var/obj/item/tool/crowbar/thrown = allocate(/obj/item/tool/crowbar)
			target.hitby(thrown, null)
		if("emag")
			var/obj/item/card/emag/card = allocate(/obj/item/card/emag)
			test_click(actor, target, card)

/// The rows one trigger produced on a fresh `type`.
/datum/unit_test/proc/dq_hit_capture(type, trigger, turf/T, mob/living/carbon/human/actor)
	rand_seed(dq_test_seed_for("[type][trigger]"))
	var/atom/target = dq_snapshot_allocate(type, T)
	if(QDELETED(target))
		return list("[trigger] | deleted itself on creation")
	if(ismachinery(target))
		var/obj/machinery/M = target
		M.stat_remove(NOPOWER|BROKEN)
	var/list/before = dq_hit_state(target)
	var/list/turf_before = dq_hit_turf_rows(T, target)
	rand_seed(dq_test_seed_for("[type][trigger]applied"))
	var/runtime = null
	try
		dq_hit_apply(target, trigger, actor)
	catch(var/exception/e)
		runtime = "[e.name]"
	test_drain()
	. = list()
	if(runtime)
		. += "[trigger] | runtime: [runtime]"

	if(QDELETED(target))
		. += "[trigger] | deleted"
	else
		var/list/after = dq_hit_state(target)
		for(var/name in after)
			if(before[name] != after[name])
				. += "[trigger] | [name]: [before[name]] -> [after[name]]"
	var/list/turf_after = dq_hit_turf_rows(T, target)
	for(var/row in turf_after)
		var/gained = turf_after[row] - (turf_before[row] || 0)
		if(gained > 0)
			. += "[trigger] | turf: +[row] x[gained]"
	for(var/row in turf_before)
		var/lost = turf_before[row] - (turf_after[row] || 0)
		if(lost > 0)
			. += "[trigger] | turf: -[row] x[lost]"
	if(!length(.))
		. += "[trigger] | nothing"
	if(!QDELETED(target))
		qdel(target)
	own_turf_contents(T)

/datum/unit_test/dq_hit_pin/Run()
	var/list/bad = list()
	var/list/expected_by_type = dq_snapshot_read_dir(DQ_HIT_PIN_DIR, bad)
	if(!length(expected_by_type) && !length(bad))
		return // no pins recorded
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	actor.enable_godmode()
	var/list/triggers = list("emp 1", "emp 2", "explosion 1", "explosion 2", "explosion 3", "projectile", "blob", "thrown", "emag")
	var/area/room = get_area(T)
	var/room_gravity = room.has_gravity
	var/list/actual_by_type = list()
	for(var/type in expected_by_type)
		if(ispath(type, /turf) || ispath(type, /mob))
			actual_by_type[type] = list("a turf or a mob is not hit-pinned")
			continue
		var/list/rows = list()
		for(var/trigger in triggers)
			rows += dq_hit_capture(type, trigger, T, actor)
		sortTim(rows, GLOBAL_PROC_REF(cmp_text_asc))
		actual_by_type[type] = rows
	if(room.has_gravity != room_gravity)
		room.gravitychange(room_gravity)
	own_turf_contents(T)
	var/report = dq_snapshot_compare(DQ_HIT_PIN_DIR, "hit_pins", actual_by_type, expected_by_type, bad)
	TEST_ASSERT(isnull(report), report)

#undef DQ_HIT_PIN_DIR
