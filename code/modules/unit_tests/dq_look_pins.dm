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
