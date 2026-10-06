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
 * Abstract types and the unit tests' uncreatables are left out; turfs and areas are not made (only objs and mobs). Each
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
			if(!ispath(type, /obj) && !ispath(type, /mob))
				continue
			if(is_abstract(type) || (type in uncreatables))
				continue
			for(var/line in dq_look_capture(type, T))
				rows += "[type] [line]"
		actual_by_type[root] = rows
	var/report = dq_snapshot_compare(DQ_LOOK_TREE_DIR, "look_trees", actual_by_type, expected_by_type, bad)
	TEST_ASSERT(isnull(report), report)

#undef DQ_LOOK_TREE_DIR

/// Makes one `type` on T (the RNG reseeded from its path), lets the presentation lane settle and returns its look rows; a
/// runtime while it is made or drawn is a row of its own, so one broken type does not end the pin.
/datum/unit_test/proc/dq_look_capture(type, turf/T)
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
		var/row = "[kind]: [MA.icon]:[MA.icon_state]:[MA.plane]"
		if(!isnull(MA.color))
			row += ":[islist(MA.color) ? jointext(MA.color, ",") : MA.color]"
		counts[row] += 1
	. = list()
	for(var/row in counts)
		. += counts[row] > 1 ? "[row] x[counts[row]]" : row
	sortTim(., GLOBAL_PROC_REF(cmp_text_asc))

#undef DQ_LOOK_PIN_DIR
