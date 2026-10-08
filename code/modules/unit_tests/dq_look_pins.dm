/**
 * Look pins: a generated snapshot of how a type looks once it exists, recorded before an appearance conversion
 * (update_icon(), APPEARANCE_TEMPLATE, DECLARE_APPEARANCE, DECLARE_APPEARANCE_PROC -> draw(look)) and checked after it.
 * Guide: doc/rewrite/snapshot_pins.md ("Look pins").
 *
 *   bash tools/dq_pin.sh --look /obj/machinery/foo [/obj/item/bar ...]   # before converting: record the pins
 *   ...convert...
 *   bash tools/dq_focused_test.sh dq_look_pin                             # after: what changed, row by row
 *
 * One file per type under code/modules/unit_tests/snapshots/looks/ (dq_snapshot_files.dm). Each type is made on the test floor,
 * the presentation lane is flushed (the init draw, the declared appearance and every queued refresh have run), and its
 * appearance is written as rows:
 *
 *   icon: <file>            state: <icon_state>        dir: <dir>
 *   color: <color>          alpha: <alpha>             (only when not the default)
 *   overlay: <icon>:<state>:<plane>[:<color>] [xN]     one row per distinct overlay (N when repeated)
 *   underlay: <icon>:<state>:<plane>[:<color>] [xN]
 *
 * A pin sees the look a type is created with, not the looks a later state change draws: the tracked-var redraws are
 * covered by the refresh-drift sweep (REFRESH DRIFT) and by hand-written tests.
 */
#define DQ_LOOK_PIN_DIR "code/modules/unit_tests/snapshots/looks/"

/datum/unit_test/dq_look_pin

/datum/unit_test/dq_look_pin/Run()
	var/list/bad = list()
	var/list/expected_by_type = dq_snapshot_read_dir(DQ_LOOK_PIN_DIR, bad)
	if(!length(expected_by_type) && !length(bad))
		return // no pins recorded
	var/turf/T = test_floor()
	var/list/actual_by_type = list()
	for(var/type in expected_by_type)
		actual_by_type[type] = dq_look_capture(type, T)
	var/report = dq_snapshot_compare(DQ_LOOK_PIN_DIR, "looks", actual_by_type, expected_by_type, bad)
	TEST_ASSERT(isnull(report), report)

/**
 * Look tree pins: the look pin of every creatable subtype under a root, in one file per root
 * (code/modules/unit_tests/snapshots/look_trees/<root>.txt), each row prefixed with its type. A conversion that rewrites
 * a whole chain (the draw sweep converts a component of related types at once) pins its roots this way:
 *
 *   bash tools/dq_pin.sh --look-tree /obj/item/gun [...]
 *
 * Abstract types and the unit tests' uncreatables are left out; a turf type is made by turning the tile east of the test floor into it (and back); areas are not made. Each
 * type is made with the RNG reseeded from its path, so a pin does not depend on the types made before it. A whole-type
 * sweep, so it runs in the exhaustive tier (and by name).
 */
#define DQ_LOOK_TREE_DIR "code/modules/unit_tests/snapshots/look_trees/"

/datum/unit_test/dq_look_tree_pin
	tier = TEST_TIER_EXHAUSTIVE
	timeout = 900

/datum/unit_test/dq_look_tree_pin/Run()
	var/list/bad = list()
	var/list/expected_by_type = dq_snapshot_read_dir(DQ_LOOK_TREE_DIR, bad)
	if(!length(expected_by_type) && !length(bad))
		return
	var/turf/T = test_floor()
	var/list/actual_by_type = list()
	for(var/root in expected_by_type)
		var/list/rows = list()
		for(var/type in typesof(root))
			if(!ispath(type, /obj) && !ispath(type, /mob) && !ispath(type, /turf))
				continue
			if(is_abstract(type) || (type in uncreatables))
				continue
			for(var/line in (ispath(type, /turf) ? dq_look_capture_turf(type, get_step(T, EAST)) : dq_look_capture(type, T)))
				rows += "[type] [line]"
		actual_by_type[root] = rows
	dq_look_drain_turf(T) // after the last capture: a capture sees what the ones before it left, so the sweep drains only at its end
	var/report = dq_snapshot_compare(DQ_LOOK_TREE_DIR, "look_trees", actual_by_type, expected_by_type, bad)
	TEST_ASSERT(isnull(report), report)

#undef DQ_LOOK_TREE_DIR

/// Makes one `type` on T (the RNG reseeded from its path), lets the presentation lane settle and returns its look rows; a
/// runtime while it is made or drawn is a row of its own, so one broken type does not end the pin.
/datum/unit_test/proc/dq_look_capture(type, turf/T)
	log_test("look pin: making [type]") // a type that hangs names itself in the log
	rand_seed(dq_test_seed_for("[type]"))
	try
		var/atom/target = dq_snapshot_allocate(type, T)
		if(QDELETED(target))
			. = list("deleted itself on creation")
		else
			appearance_flush()
			. = dq_look_pin_lines(target)
			qdel(target)
	catch(var/exception/e)
		var/static/regex/where = regex(@"^\S+\.dm:\d+:")
		. = list("runtime: [where.Replace(e.name, "")]") // without the file and line, which move with unrelated edits
	own_turf_contents(T)

/// Deletes what the captures left on `T` until nothing is left. Deleting a thing can make more of them (a space worm's destroyed
/// segment severs the back half into a new dead head, which severs its own back half when it is deleted in turn), so one pass,
/// or leaving them for the block's release, ends with the last of them on the block as a leak.
/datum/unit_test/proc/dq_look_drain_turf(turf/T)
	for(var/pass in 1 to 30)
		var/list/left = list()
		for(var/atom/movable/AM as anything in contents_of(T))
			if(!QDELETED(AM) && !istype(AM, /obj/effect/landmark))
				left += AM
		if(!length(left))
			return
		for(var/atom/movable/AM as anything in left)
			if(!QDELETED(AM))
				qdel(AM)

/// dq_look_capture() for a turf type: `spot` is turned into it, drawn and turned back. The made turf is the look; the RNG is reseeded from the path.
/datum/unit_test/proc/dq_look_capture_turf(type, turf/spot)
	var/old_type = spot.type
	log_test("look pin: making [type]")
	rand_seed(dq_test_seed_for("[type]"))
	try
		var/turf/made = spot.ChangeTurf(type)
		if(QDELETED(made))
			. = list("deleted itself on creation")
		else
			appearance_flush()
			. = dq_look_pin_lines(made)
	catch(var/exception/e)
		var/static/regex/where = regex(@"^\S+\.dm:\d+:")
		. = list("runtime: [where.Replace(e.name, "")]")
	var/turf/restored = locate(spot.x, spot.y, spot.z)
	restored.ChangeTurf(old_type)

/// The look rows of one atom (see the file comment), sorted so the file diffs cleanly.
/proc/dq_look_pin_lines(atom/target)
	. = list()
	. += "icon: [target.icon]"
	. += "state: [target.icon_state]"
	. += "dir: [target.dir]"
	if(!isnull(target.color))
		. += "color: [islist(target.color) ? jointext(target.color, ",") : target.color]"
	if(target.alpha != 255)
		. += "alpha: [target.alpha]"
	. += dq_look_pin_layers("overlay", target.overlays)
	. += dq_look_pin_layers("underlay", target.underlays)

/// One row per distinct layer of `layers` (an overlays or underlays list), "xN" when it is there N times.
/proc/dq_look_pin_layers(kind, list/layers)
	var/list/counts = list()
	for(var/layer in layers)
		var/mutable_appearance/MA = new(layer)
		if(MA.icon == LIGHTING_ICON) // the lighting system's own darkness layer, present or not by boot timing; not part of a look
			continue
		var/row = "[kind]: [MA.icon]:[MA.icon_state]:[MA.plane]"
		if(!isnull(MA.color))
			row += ":[islist(MA.color) ? jointext(MA.color, ",") : MA.color]"
		counts[row] += 1
	. = list()
	for(var/row in counts)
		. += counts[row] > 1 ? "[row] x[counts[row]]" : row
	sortTim(., GLOBAL_PROC_REF(cmp_text_asc))

#undef DQ_LOOK_PIN_DIR

/**
 * Look state pins: how each creatable subtype of a root looks after the state its look reacts to changes, one file per root
 * (code/modules/unit_tests/snapshots/look_states/<root>.txt). A look tree pin sees only the look a type is made with; this one
 * moves state and records the look again:
 *
 *   bash tools/dq_pin.sh --look-state /obj/item/gun [...]
 *
 * Per type, for each numeric var the type declares below its base (/obj or /mob; at most DQ_LOOK_STATE_MAX_VARS of them, in
 * declaration order), a fresh instance has the var written (0, 1 and 2, whichever differ from its made value; through its tracked
 * setter when it has one, else the raw var), a redraw requested the way a caller does (update_icon(), then changed()), the
 * presentation lane flushed, and the look compared with the made look. A row is the probe and what the look gained or lost:
 *
 *   <type> <var>=<n> +overlay: ...        <type> <var>=<n> -state: ...        <type> <var>=<n> runtime: <message>
 *
 * A probe that changes nothing writes no row, so a var the look ignores is silent and a conversion that makes it matter shows.
 * The rows are the look a conversion must keep: the same file before and after.
 */
#define DQ_LOOK_STATE_DIR "code/modules/unit_tests/snapshots/look_states/"
#define DQ_LOOK_STATE_MAX_VARS 24

/datum/unit_test/dq_look_state_pin
	tier = TEST_TIER_EXHAUSTIVE
	timeout = 1800

/datum/unit_test/dq_look_state_pin/Run()
	var/list/bad = list()
	var/list/expected_by_type = dq_snapshot_read_dir(DQ_LOOK_STATE_DIR, bad)
	if(!length(expected_by_type) && !length(bad))
		return
	var/turf/T = test_floor()
	var/list/base_vars_obj = dq_look_state_base_vars(/obj, T)
	var/list/base_vars_mob = dq_look_state_base_vars(/mob, T)
	var/list/actual_by_type = list()
	for(var/root in expected_by_type)
		var/list/rows = list()
		for(var/type in typesof(root))
			if(!ispath(type, /obj) && !ispath(type, /mob))
				continue
			if(is_abstract(type) || (type in uncreatables))
				continue
			rows += dq_look_state_rows(type, T, ispath(type, /obj) ? base_vars_obj : base_vars_mob)
		actual_by_type[root] = rows
	var/report = dq_snapshot_compare(DQ_LOOK_STATE_DIR, "look_states", actual_by_type, expected_by_type, bad)
	TEST_ASSERT(isnull(report), report)

/// The var names of the base type `base`: what a probe leaves alone.
/datum/unit_test/proc/dq_look_state_base_vars(base, turf/T)
	var/atom/A = allocate(base, T)
	. = list()
	for(var/name in A.vars)
		. += name
	qdel(A)
	own_turf_contents(T)

/// The probe rows of one type (see the pin's comment).
/datum/unit_test/proc/dq_look_state_rows(type, turf/T, list/base_vars)
	. = list()
	var/list/names = list()
	try
		var/atom/probe = dq_snapshot_allocate(type, T)
		if(QDELETED(probe))
			return
		for(var/name in probe.vars)
			if(name in base_vars)
				continue
			if(isnum(probe.vars[name]) && !findtext(name, "time") && !findtext(name, "cooldown") && !findtext(name, "last") && !findtext(name, "next"))
				names += name
		qdel(probe)
	catch(var/exception/e)
		. += "[type] runtime: [dq_look_state_error(e)]"
		dq_look_drain_turf(T)
		return
	dq_look_drain_turf(T)
	if(length(names) > DQ_LOOK_STATE_MAX_VARS)
		names.Cut(DQ_LOOK_STATE_MAX_VARS + 1)
	var/list/base = dq_look_capture(type, T)
	dq_look_drain_turf(T)
	for(var/name in names)
		for(var/value in list(0, 1, 2))
			. += dq_look_state_probe(type, T, name, value, base)

/// One probe: a fresh `type` with `name` written to `value`, redrawn, against the made look `base`; rows only for a difference.
/datum/unit_test/proc/dq_look_state_probe(type, turf/T, name, value, list/base)
	. = list()
	rand_seed(dq_test_seed_for("[type]/[name]=[value]"))
	try
		var/atom/target = dq_snapshot_allocate(type, T)
		if(QDELETED(target))
			return
		appearance_flush()
		if(target.vars[name] == value)
			qdel(target)
			dq_look_drain_turf(T)
			return
		var/setter = "set_[name]"
		if(hascall(target, setter))
			call(target, setter)(value)
		else
			target.vars[name] = value
		target.update_icon()
		changed(target)
		appearance_flush()
		var/list/now = dq_look_pin_lines(target)
		for(var/row in now - base)
			. += "[type] [name]=[value] +[row]"
		for(var/row in base - now)
			. += "[type] [name]=[value] -[row]"
		qdel(target)
	catch(var/exception/e)
		. += "[type] [name]=[value] runtime: [dq_look_state_error(e)]"
	// A probe leaves nothing behind: what its thing spilled when it was deleted (a core's chunk, a cabinet's guns, a worm's dead
	// heads) would otherwise be there for every later probe, and a closet takes all of it in each time it is made, so a type's
	// probes got slower with each one and the sweep never finished.
	dq_look_drain_turf(T)

/proc/dq_look_state_error(exception/e)
	var/static/regex/where = regex(@"^\S+\.dm:\d+:")
	return where.Replace(e.name, "")

#undef DQ_LOOK_STATE_DIR
#undef DQ_LOOK_STATE_MAX_VARS

/// A state-pin probe of a type that spills things when it dies (a blob core drops a chunk, a gun cabinet its guns) leaves the floor
/// clear, so a closet made after it takes nothing in: the cost of a probe stays the same however many came before it.
/datum/unit_test/dq_look_state_probe_leaves_floor_clear

/datum/unit_test/dq_look_state_probe_leaves_floor_clear/Run()
	var/turf/T = test_floor()
	var/list/base_vars = dq_look_state_base_vars(/obj, T)
	for(var/type in list(/obj/structure/blob/core, /obj/structure/closet/secure_closet/guncabinet/sidearm))
		dq_look_state_rows(type, T, base_vars)
		var/list/left = list()
		for(var/atom/movable/AM as anything in contents_of(T))
			if(!QDELETED(AM) && !istype(AM, /obj/effect/landmark))
				left += AM
		TEST_ASSERT(!length(left), "[type]'s probes left [length(left)] things on the floor ([left[1]?.type])")
	var/obj/structure/closet/C = allocate(/obj/structure/closet/coffin, T)
	TEST_ASSERT(!length(C.contents), "a closet made after the probes took in [length(C.contents)] things")
