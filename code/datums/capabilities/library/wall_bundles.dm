// TEMPORARY (rewrite/dx-apc): the lead's wall_machine() / maintenance_hatch() bundles land on
// rewrite/dx-framework. These local definitions have the names and signatures the APC is written
// against; DROP wall_machine() and maintenance_hatch() at that merge (keep cap_wall_mount and
// cap_hatch_rules if the lead's bundles carry no equivalent).

/// A wall-mounted machine: it hangs on the wall (cap_wall_mount) and breaks (no welder repair: its own
/// steps mend it). `board` names the electronics it is built with (wall_board_of()).
/proc/wall_machine(board, offset = WALL_MOUNT_OFFSET)
	return list(
		cap_wall_mount(offset = offset, board = board),
		cap_layer_order(cap_breakable(repair_tool = NONE), 30),
	)

/**
 * A maintenance hatch: a crowbar cover, a screwdriver panel with `wires_type` behind it, and an access
 * lock swiped with the hatch shut. `cover_locked_while`: holder proc (mob/user, obj/item/held) -> null
 * or FALSE while the cover may move, TRUE or a reason while it holds. `panel_needs_cover_closed`: the
 * panel (and the wires behind it) work only with the cover closed. The lock draws no layer (the
 * holder shows it as its own glow).
 */
/proc/maintenance_hatch(wires_type, access, cover_locked_while, panel_needs_cover_closed = FALSE)
	var/shut = panel_needs_cover_closed ? COVER : NONE
	. = list(
		cap_layer_order(cap_cover(open_tool = TOOL_CROWBAR), 40),
		cap_layer_order(cap_panel(tool = TOOL_SCREWDRIVER, blocked_by = shut), 20),
		cap_wires(wires_type, behind = PANEL, blocked_by = shut, layer = CAP_NO_LAYER),
		cap_lock(access = access ? list(access) : null, blocked_by = COVER | PANEL, layer = CAP_NO_LAYER),
	)
	if(cover_locked_while)
		. += cap_hatch_rules(cover_locked_while)

// ---- cap_wall_mount ----

/datum/capability/wall_mount
	layer_name = CAP_NO_LAYER
	/// Pixels from the turf centre into the wall.
	var/offset = WALL_MOUNT_OFFSET
	/// The electronics type it is built with.
	var/board

/// Hangs the holder on the wall behind it at init: `offset` pixels along its dir, unless the map placed
/// it by hand (pixel_x / pixel_y set).
/proc/cap_wall_mount(offset = WALL_MOUNT_OFFSET, board)
	var/datum/capability/wall_mount/C = new
	C.offset = offset
	C.board = board
	return C

/datum/capability/wall_mount/on_holder_init(atom/holder, mapload)
	if(!holder.pixel_x && !holder.pixel_y)
		holder.wall_mount_orient()

/// Offsets the holder into the wall along its dir by its wall mount's offset. Types with an odd sprite
/// (angled wall machines) override it.
/atom/proc/wall_mount_orient()
	var/datum/capability/wall_mount/C = cap_of(src, /datum/capability/wall_mount)
	var/offset = C ? C.offset : WALL_MOUNT_OFFSET
	pixel_x = (dir & (NORTH|SOUTH)) ? 0 : (dir == EAST ? offset : -offset)
	pixel_y = (dir & (NORTH|SOUTH)) ? (dir == NORTH ? offset : -offset) : 0

/// The electronics type A's wall mount was declared with, or null.
/proc/wall_board_of(atom/A)
	var/datum/capability/wall_mount/C = cap_of(A, /datum/capability/wall_mount)
	return C?.board

// ---- cap_hatch_rules: the cover lock ----

/datum/capability/hatch_rules
	layer_name = CAP_NO_LAYER
	/// Holder proc (mob/user, obj/item/held): TRUE or a reason while the cover holds.
	var/cover_locked_while

/// Refuses the cover's entries while the holder proc `cover_locked_while` says the cover holds.
/proc/cap_hatch_rules(cover_locked_while)
	var/datum/capability/hatch_rules/C = new
	C.cover_locked_while = cover_locked_while
	return C

/datum/capability/hatch_rules/gate(atom/holder, mob/user, datum/interaction/entry)
	var/datum/interaction/capability/E = entry
	if(!istype(E) || !istype(E.cap, /datum/capability/cover))
		return null
	var/holds = call(holder, cover_locked_while)(user, null)
	if(!holds)
		return null
	return istext(holds) ? holds : "the cover is locked"
