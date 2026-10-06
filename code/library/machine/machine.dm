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

// ---- STAT_OPERABLE's conditions ----
// A machine works while it is whole and not under maintenance (and has power: machinery.dm). They are contributions of the base machine with keys, so a
// type that says its own (the APC, the SMES, the self-powered turret) drops them with without().

/// The machine works (STAT_OPERABLE), else "It isn't working." The requirement of every control a dead machine refuses.
/proc/req_operable()
	return req_is(STAT_OPERABLE, because = MSG(machine/inoperable))

/// The actor stands on the holder's turf (a machine worked from inside its own tile: a holomap, a pad). Followed through both
/// movements, so a cached menu updates when either moves.
/proc/req_on_holder_turf(because = null)
	return part_make(/datum/entry/part/req/on_holder_turf, list("because" = because))

/datum/entry/part/req/on_holder_turf
	part_name = "req_on_holder_turf"
	default_reason = /datum/msg/op/unreachable

/datum/entry/part/req/on_holder_turf/read_keys(datum/act/op/A)
	. = list()
	if(A.actor)
		. += list(list(A.actor, OP_KEEP_MOVED))
	if(A.holder)
		. += list(list(A.holder, OP_KEEP_MOVED))

/datum/entry/part/req/on_holder_turf/holds(datum/act/op/A)
	var/atom/movable/holder = A.holder
	var/mob/actor = A.actor
	return istype(holder) && istype(actor) && !isnull(holder.loc) && actor.loc == holder.loc

/// The held item can leave what holds it (nothing keeps it there: a sticky trait, a ledger slot that refuses): the item() op that puts
/// it somewhere says why it can't before it is tried. The reason is the release refusal itself.
/proc/req_held_releasable()
	return part_make(/datum/entry/part/req/held_releasable)

/datum/entry/part/req/held_releasable
	part_name = "req_held_releasable"
	default_reason = /datum/msg/req_wrong_item

/datum/entry/part/req/held_releasable/read_keys(datum/act/op/A)
	return A.actor ? list(list(A.actor, OP_KEEP_HAND)) : list()

/datum/entry/part/req/held_releasable/holds(datum/act/op/A)
	return isnull(held_release_reason(A))

/datum/entry/part/req/held_releasable/refusal(datum/act/op/A)
	return held_release_reason(A) || ..()

/// Why A.held can't leave what holds it (the actor's hand, a bag, a slot), or null.
/proc/held_release_reason(datum/act/op/A)
	READS_FROM(A)
	if(!A.held)
		return null
	return A.held.loc?.release_refusal(A.held, A.actor)

/// The machine is broken (the BROKEN bit atom_break() sets): what breakable() draws and says.
/obj/machinery/proc/stat_is_broken(datum/act/A)
	return broken_now()

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
	return istype(M) && M.broken_now()

// ---- the wall mount ----

CAPABILITY_TYPE(wall_mount, CAP_WALL_MOUNT, /datum/capability/lib/wall_mount, key = NONE, offset = 26, offset_ns = null)

/// A wall-mounted holder faces away from its wall and sits `offset` pixels onto it (`offset_ns` when it faces north or south, for a sprite that
/// sits closer on that side). A mapped dir is kept (maps place wall machines facing the room); a holder built at runtime with no dir set looks
/// for the wall around it.
/datum/capability/lib/wall_mount
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/wall_mount/on_holder_init(datum/act/eval/A)
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

CAPABILITY_DEF(machine_basics, CAP_MACHINE_BASICS, key = NONE, board = null, repair = TOOL_WELDER, frame = null, powered = TRUE, area_power = TRUE)

/// The machine core's own: breakable with welder repair (`repair` = NONE: none), powered (`powered` = FALSE: a machine whose look says its own),
/// the build ladder `frame` (a construction(...) capability, NONE for none), the claws' slash, STAT_OPERABLE's bridge, and the rule that every
/// control needs a machine that works.
/datum/capability/def/machine_basics/entries()
	var/list/entries = list(
		breakable(repair),
		op("slash", hand(), label("Slash"), priority(OP_PRIORITY_CLAW), \
			when(TYPE_PROC_REF(/atom, claw_slash_offered)), \
			then(TYPE_PROC_REF(/atom, claw_slash)), says(MSG(machine/slash))),
		extend(TAG_CONTROL, needs(req_operable())))
	if(powered)
		entries += powered()
	if(!area_power)
		entries += without("area_power") // ALLOW(keys): without() drops an inherited contributes() entry by its key, not an op
		entries += without("power_operable") // ALLOW(keys): without() drops an inherited contributes() entry by its key, not an op
		entries += without("maint_operable") // ALLOW(keys): without() drops an inherited contributes() entry by its key, not an op // a machine that says its own power (the APC, the SMES, a self-powered turret) is not darkened by its area's channel
	if(frame && frame != NONE)
		entries += frame
	return entries

CAPABILITY_DEF(wall_machine, CAP_WALL_MACHINE, key = NONE, board = null, repair = TOOL_WELDER, frame = null, powered = TRUE, area_power = TRUE, offset = 26, offset_ns = null)

/// machine_basics() without anchoring (it hangs on the wall), plus the wall mount.
/datum/capability/def/wall_machine/entries()
	return list(machine_basics(board, repair, frame, powered, area_power), wall_mount(offset, offset_ns))

/// The actor has claws that tear machines open (a species that can_shred() at `force`: a windoor asks 15).
/proc/req_can_shred(force = 14)
	return part_make(/datum/entry/part/req/can_shred, list("force" = force))

/datum/entry/part/req/can_shred
	part_name = "req_can_shred"
	default_reason = /datum/msg/req_no_claws

/datum/entry/part/req/can_shred/holds(datum/act/op/A)
	var/mob/living/carbon/human/H = A.actor
	return istype(H) && H.species?.can_shred(H, FALSE, src.args?["force"] || 14)

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

CAPABILITY_TYPE(maintenance_hatch, CAP_MAINTENANCE_HATCH, /datum/capability/lib/maintenance_hatch, key = NONE, cover = null, wires = null, emag = null, lock = TRUE, panel_needs_cover_closed = FALSE, starts_locked = FALSE, emag_say = null, lock_wire = null)

/// space(SPACE_HATCH, door = CAP_COVER), the cover you pass (a crowbar's by default), the panel (and its space SPACE_PANEL), the wires when given (a whole wires(...) entry),
/// the ID lock (`lock_wire`: the wire it brings and needs intact) and the emag when given, and the rules between them: the ID lock and the emag work only
/// with the cover and the panel closed (req_closed()), and the panel is latched shut while the cover is open when panel_needs_cover_closed. A
/// machine passes its wires and its emag effect here instead of declaring wires and emag again. What sits behind the cover (a cell bay, a
/// build ladder) works at(SPACE_HATCH).
///
/// The hatch is where every tool on a wall machine meets something, so it says ONCE which answers a click when several could: a construction step
/// before the panel (screwdriver) and the wires (wirecutters), the subversion reset before the wires (multitool), and for an empty hand the
/// construction step, then the wires, then the machine's window. A type that has these needs no priority(above(...)) of its own.
/datum/capability/lib/maintenance_hatch
	holder_hooks = HOLDER_HOOK_INIT
	output_hooks = OUTPUT_HOOK_DRAW

/datum/capability/lib/maintenance_hatch/entries()
	var/list/closed_up = list(req_closed(SPACE_HATCH), req_closed(SPACE_PANEL))
	var/list/entries = list(
		space(SPACE_HATCH, door = CAP_COVER),
		cover || cover(),
		panel())
	if(wires)
		entries += wires // a whole wires(...) entry: its name, count, lights, reach and the rest
	if(lock)
		entries += lock(starts_locked = starts_locked, wire = lock_wire)
		entries += extend("lock.toggle", needs(closed_up))
		entries += extend("lock.toggle_worn", needs(closed_up))
	if(emag)
		entries += emag(emag, say = emag_say)
		entries += extend("emag.use", needs(closed_up))
	if(panel_needs_cover_closed)
		entries += latch(SPACE_PANEL, COVER_OPEN, because = MSG(hatch/close_cover))
	// the canonical click order of the hatch's tools (click_order(), code/engine/parts/plan.dm)
	entries += click_order(TOOL_SCREWDRIVER, list("construction.build:*", "construction.undo:*"), "panel.open")
	entries += click_order(TOOL_WIRECUTTER, "construction.undo:*", "wires.cut")
	entries += click_order(TOOL_MULTITOOL, "subversion_reset.use", "wires.pulse")
	entries += click_order(BIND_HAND, "construction.undo:*", "wires.open", "ui_open")
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
