// The machine bundles and their parts (doc/rewrite/final_api.html, section 11 "Bundles and capabilities"):
// breakable(repair =), wall_mount(offset), machine_basics(board, repair =, frame =, powered =), wall_machine(...) and maintenance_hatch(...).
//
// The three bundles are capabilities, so without(CAP_MACHINE_BASICS) and configure(CAP_MACHINE_BASICS, frame = NONE) work. What the machine core
// still keeps as stat bits (BROKEN, NOPOWER, POWEROFF, MAINT, EMPED: code/game/machinery/machinery_fields.dm) reaches STAT_OPERABLE through ONE
// bridge contribution, stat_bits_allow(), which phase 4 (the machine track) deletes when each bit becomes the contribution of the capability
// that owns it. Until then `operable` of a converted machine is the same fact as the legacy operable() proc.

MSG_DEF_SELF(machine/inoperable, "It isn't working.")
MSG_DEF_SELF(hatch/close_cover, "Close the cover first.")
MSG_DEF_SELF(hatch/close_panel, "Close the maintenance panel first.")
MSG_DEF_SELF(breakable/not_broken, "It isn't broken.")
MSG_DEF(breakable/repaired, "You repair %T%.", "%U% repairs %T%.")
MSG_DEF_SELF(breakable/examine, "It is broken.")
MSG_DEF(machine/slash, "You slash at %T%!", "%U% slashes at %T%!")

// ---- the legacy stat bits, as one contribution ----

/// STAT_OPERABLE's reading of the machine core's condition bits: none of BROKEN, NOPOWER, POWEROFF, MAINT, EMPED is set. Written once, here, and
/// deleted with the bits (phase 4).
/obj/machinery/proc/stat_bits_allow(datum/act/A)
	return !has_stat(MACHINE_INOPERABLE_FLAGS)

/// The machine is broken (the BROKEN bit atom_break() sets): what breakable() draws and says.
/obj/machinery/proc/stat_is_broken(datum/act/A)
	return has_stat(BROKEN)

// ---- breakable ----

CAPABILITY_TYPE(breakable, CAP_BREAKABLE, /datum/capability/lib/breakable, key = NONE, repair = TOOL_WELDER)

/datum/capability/lib/breakable

/datum/capability/lib/breakable/entries()
	var/list/entries = list(
		look_layer(LOOK_BROKEN, when = TYPE_PROC_REF(/obj/machinery, stat_is_broken), reads = list("stat")),
		examine_line(MSG(breakable/examine), when = TYPE_PROC_REF(/obj/machinery, stat_is_broken), reads = list("stat")))
	if(repair && repair != NONE)
		entries += op("repair", tool(repair), needs(req(CAP_PROC(is_broken), because = MSG(breakable/not_broken))), fixes(), says(MSG(breakable/repaired)))
	return entries

/datum/capability/lib/breakable/proc/is_broken(datum/act/A)
	var/obj/machinery/M = A.holder
	return istype(M) && M.has_stat(BROKEN)

// ---- the wall mount ----

CAPABILITY_TYPE(wall_mount, CAP_WALL_MOUNT, /datum/capability/lib/wall_mount, key = NONE, offset = 26, offset_ns = null)

/// A wall-mounted holder faces away from its wall and sits `offset` pixels onto it (`offset_ns` when it faces north or south, for a sprite that
/// sits closer on that side). A mapped dir is kept (maps place wall machines facing the room); a holder built at runtime with no dir set looks
/// for the wall around it.
/datum/capability/lib/wall_mount
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/wall_mount/on_holder_init_ctx(datum/act/eval/A)
	var/atom/holder = A.holder
	if(!A.mapload)
		var/turf/here = get_turf(holder)
		for(var/direction in GLOB.cardinal)
			var/turf/T = get_step(here, direction)
			if(iswall(T))
				holder.set_dir(REVERSE_DIR(direction))
				break
	// A holder the map placed by hand (pixel_x / pixel_y set) stays where it was put.
	if(!holder.pixel_x && !holder.pixel_y)
		orient(holder)

/// Sits the holder onto the wall behind it (toward its dir).
/datum/capability/lib/wall_mount/proc/orient(atom/holder)
	var/along = (holder.dir & (NORTH|SOUTH)) ? (isnull(offset_ns) ? offset : offset_ns) : offset
	holder.pixel_x = (holder.dir & (NORTH|SOUTH)) ? 0 : (holder.dir == EAST ? along : -along)
	holder.pixel_y = (holder.dir & (NORTH|SOUTH)) ? (holder.dir == NORTH ? along : -along) : 0

/// Re-sits A onto its wall after its dir changed (nothing without a wall mount).
/proc/wall_mount_orient(atom/A)
	var/datum/capability/lib/wall_mount/C = cap_of(A, CAP_WALL_MOUNT)
	C?.orient(A)

// ---- machine basics ----

CAPABILITY_DEF(machine_basics, CAP_MACHINE_BASICS, key = NONE, board = null, repair = TOOL_WELDER, frame = null, powered = TRUE)

/// The machine core's own: breakable with welder repair (`repair` = NONE: none), powered (`powered` = FALSE: a machine whose look says its own),
/// the build ladder `frame` (a construction(...) capability, NONE for none), the claws' slash, STAT_OPERABLE's bridge, and the rule that every
/// control needs a machine that works.
/datum/capability/def/machine_basics/entries()
	var/list/entries = list(
		breakable(repair),
		contributes(STAT_OPERABLE, TYPE_PROC_REF(/obj/machinery, stat_bits_allow), reason = MSG(machine/inoperable), reads = list("stat")),
		op("slash", hand(), label("Slash"), priority(OP_PRIORITY_CLAW), \
			when(TYPE_PROC_REF(/atom, claw_slash_offered)), \
			then(TYPE_PROC_REF(/atom, claw_slash)), says(MSG(machine/slash))),
		extend(TAG_CONTROL, needs(req_is(STAT_OPERABLE, because = MSG(machine/inoperable)))))
	if(powered)
		entries += powered()
	if(frame && frame != NONE)
		entries += frame
	return entries

CAPABILITY_DEF(wall_machine, CAP_WALL_MACHINE, key = NONE, board = null, repair = TOOL_WELDER, frame = null, powered = TRUE, offset = 26, offset_ns = null)

/// machine_basics() without anchoring (it hangs on the wall), plus the wall mount.
/datum/capability/def/wall_machine/entries()
	return list(machine_basics(board, repair, frame, powered), wall_mount(offset, offset_ns))

/// The actor has claws that tear machines open (a species that can_shred()).
/proc/req_can_shred()
	return part_make(/datum/entry/part/req/can_shred)

/datum/entry/part/req/can_shred
	part_name = "req_can_shred"
	default_reason = /datum/msg/req_no_claws

/datum/entry/part/req/can_shred/holds(datum/act/op/A)
	var/mob/living/carbon/human/H = A.actor
	return istype(H) && H.species?.can_shred(H, FALSE, 14)

/// The slash is offered to a bare hand with claws, on a holder something hears the slash of (anything else the touch means is left alone).
/atom/proc/claw_slash_offered(datum/act/op/A)
	var/mob/living/carbon/human/H = A.actor
	return isnull(A.held) && istype(H) && H.species?.can_shred(H, FALSE, 14) && op_notice_wanted(A.target, /datum/notice/slashed)

/// The slash's work: its cooldown, the noise, the prints, and the holder hears it (a type that listens, on_notice(/datum/notice/slashed), decides what gives).
/atom/proc/claw_slash(datum/act/op/A)
	var/mob/living/carbon/human/user = A.actor
	user.setClickCooldown(user.get_attack_speed())
	play_sfx(src, SFX_WEAPONS_SLASH, 2)
	add_hiddenprint(user)
	PUBLISH(src, slash, slasher = user)
	return OP_OK

// ---- the maintenance hatch ----

CAPABILITY_TYPE(maintenance_hatch, CAP_MAINTENANCE_HATCH, /datum/capability/lib/maintenance_hatch, key = NONE, cover = null, wires = null, emag = null, lock = TRUE, panel_needs_cover_closed = FALSE, starts_locked = FALSE, emag_say = null)

/// compartment(BAY_HATCH, door = CAP_COVER), the cover you pass (a crowbar's by default), the panel, the wires when given, the ID lock and the emag
/// when given, and the rules between them: the ID lock and the emag work only with the cover and the panel closed, and the panel opens only with
/// the cover closed when panel_needs_cover_closed. A machine passes its wire set and its emag effect here instead of declaring wires and emag again.
/// What sits behind the cover (a cell bay, a build ladder) works at(BAY_HATCH).
/datum/capability/lib/maintenance_hatch
	holder_hooks = HOLDER_HOOK_INIT
	output_hooks = OUTPUT_HOOK_DRAW

/datum/capability/lib/maintenance_hatch/entries()
	var/list/closed_up = list(
		req_is(COVER_OPEN, FALSE, because = MSG(hatch/close_cover)),
		req_is(PANEL_OPEN, FALSE, because = MSG(hatch/close_panel)))
	var/list/entries = list(
		compartment(BAY_HATCH, door = CAP_COVER),
		cover || cover(),
		panel())
	if(wires)
		entries += wires(wires)
	if(lock)
		entries += lock(starts_locked = starts_locked)
		entries += extend("lock.toggle", needs(closed_up))
		entries += extend("lock.toggle_worn", needs(closed_up))
	if(emag)
		entries += emag(emag, say = emag_say)
		entries += extend("emag.use", needs(closed_up))
	if(panel_needs_cover_closed)
		entries += extend("panel.open", needs(req_is(COVER_OPEN, FALSE, because = MSG(hatch/close_cover))))
	return entries

/// The lock shows as a lamp (locked or unlocked, glowing) and the emag as the emagged screen while the machine is lit and closed up.
/datum/capability/lib/maintenance_hatch/on_draw(datum/act/eval/A, datum/look/look)
	var/atom/holder = A.holder
	if(cover_open(holder, null) || panel_open(holder))
		return
	if(lock && is_lit(holder))
		look.glow(lock_locked(holder) ? LOOK_LOCKED : LOOK_UNLOCKED)
	if(emag)
		look.part(LOOK_EMAGGED, emag_emagged(holder))

GLOBAL_LIST_INIT(hatch_output_reads, list("stat"))

/datum/capability/lib/maintenance_hatch/output_reads(hook)
	return GLOB.hatch_output_reads
