// The fixtures of the phase-2 engine pieces: the hit bridge (receive_damage() runs the hit action of the engine, code/game/atom/damage_packet.dm) and
// ruined() in a state-graph dismantle (code/engine/parts/graph_ops.dm). Test-only types, compiled under UNIT_TESTS only
// (code/modules/unit_tests/dq_p2_engine_tests.dm drives them).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// ---- the hit bridge ----

/// A damageable object nothing hooks: it takes the damage as it always did.
/obj/p2_hit
	name = "p2 hit target"
	uses_integrity = TRUE
	max_integrity = 100
	/// What the hooks and reactions counted.
	var/took = 0
	var/heard = 0
	var/legacy = 0
	/// The integrity the after hook saw: the notice comes after the sink.
	var/integrity_when_heard = -1

/obj/p2_hit/plain

/// An EMP is taken over by an instead.
/obj/p2_hit/taker

CAPABILITIES(/obj/p2_hit/taker, \
	extend(/datum/act/hit/emp, instead(then(PROC_REF(take_over)))))

/obj/p2_hit/taker/proc/take_over(datum/act/A)
	took++

/// Halves every hit through the generic hit, and refuses fire.
/obj/p2_hit/halver

CAPABILITIES(/obj/p2_hit/halver, \
	extend(/datum/act/hit, adjusts(packet.amounts, scale = 0.5)), \
	extend(/datum/act/hit/fire, needs(req(PROC_REF(never), because = MSG(p1/not_ready)))))

/obj/p2_hit/halver/proc/never(datum/act/A)
	return FALSE

/// Hears a blob hit after it landed.
/obj/p2_hit/listener

CAPABILITIES(/obj/p2_hit/listener, \
	on_notice(/datum/notice/hit/blob, then(PROC_REF(hear))))

/obj/p2_hit/listener/proc/hear(datum/act/A)
	heard++
	integrity_when_heard = get_integrity()

/// An EMP reaction of the legacy form: before_op(damage(DAMAGE_EMP)), blocking when `legacy_blocks`.
/obj/p2_hit/legacy
	var/legacy_blocks = TRUE

DAMAGE_REACTION(/obj/p2_hit/legacy, DAMAGE_EMP, PROC_REF(legacy_emp))

/obj/p2_hit/legacy/proc/legacy_emp(datum/damage_packet/packet)
	legacy++
	return legacy_blocks ? DAMAGE_REACTION_BLOCK : 0

/// Both forms: the new hook halves the EMP, then the legacy row (which does not block) runs and the sink lands what is left.
/obj/p2_hit/both
	var/legacy_blocks = FALSE

CAPABILITIES(/obj/p2_hit/both, \
	extend(/datum/act/hit/emp, adjusts(packet.amounts, scale = 0.5)))

DAMAGE_REACTION(/obj/p2_hit/both, DAMAGE_EMP, PROC_REF(legacy_emp))

/obj/p2_hit/both/proc/legacy_emp(datum/damage_packet/packet)
	legacy++
	return 0

// ---- ruined() in dismantle ----

/// A frame with a one-stage build and a dismantle that is ruined when `wrecked`: a reusable frame item, or scrap.
/obj/p2_frame
	name = "p2 frame"
	var/wrecked = FALSE

/obj/p2_frame/proc/frame_ruined(datum/act/A)
	return wrecked

/obj/item/p2_frame_item
	name = "p2 frame item"

/obj/item/p2_scrap
	name = "p2 scrap"

CAPABILITIES(/obj/p2_frame, \
	construction(start(STAGE_DOOR_FRAME), \
		stage(STAGE_DOOR_WIRED, stack(/obj/item/stack/cable_coil, 5), undo = null), \
		dismantle(tool(TOOL_CROWBAR), wait(0), becomes(/obj/item/p2_frame_item), \
			ruined(TYPE_PROC_REF(/obj/p2_frame, frame_ruined), becomes(/obj/item/p2_scrap)))))

// ---- the machine library: a box with a hatch (code/library/machine, code/library/access, code/engine/present) ----

/datum/wires/p2_box
	holder_type = /obj/machinery/p2_box
	wire_count = 2
	proper_name = "p2 box"

/datum/wires/p2_box/New(atom/_holder)
	wires = list(WIRE_IDSCAN, WIRE_AI_CONTROL)
	return ..()

/datum/wires/p2_box/interactable(mob/user)
	return TRUE

MSG_DEF_SELF(p2/ui_forbidden, "That is not allowed.")

/// A machine with a cover, a panel, wires, an ID lock, an emag and a cell bay behind the cover, a window with one button, a wait whose length a
/// proc says, and a build graph placed finished.
/obj/machinery/p2_box
	name = "p2 box"
	req_access = list(ACCESS_ENGINE_EQUIP)
	var/obj/item/cell/cell
	var/lock_at_start = TRUE
	var/emag_ran = 0
	var/pressed_with = null
	var/fitting_time = 20
	var/fitted = 0
	var/label_shown = TRUE

TRACKED(/obj/machinery/p2_box, label_shown)

CAPABILITIES(/obj/machinery/p2_box, 	machine_basics(null, repair = NONE, frame = NONE, powered = FALSE), 	maintenance_hatch( 		cover = cover(open = tool(TOOL_CROWBAR)), 		wires = /datum/wires/p2_box, 		emag = list(then(PROC_REF(emag_effect))), 		panel_needs_cover_closed = TRUE, 		starts_locked = nameof(lock_at_start)), 	owns_one(nameof(cell), /obj/item/cell, on_destroy = ON_DESTROY_SPILL), 	cell_bay(nameof(cell), at = BAY_HATCH), 	interface("P2Box"), 	look_layer("p2-label", when = nameof(label_shown)), 	examine_line(MSG(p2/ui_forbidden), when = cond_not(nameof(label_shown))), 	op("press", ui_act(arg("n", int(0, 9))), then(PROC_REF(pressed))), 	op("fit", tool(TOOL_WRENCH), wait(PROC_REF(fit_wait)), then(PROC_REF(fitted_now))))

/obj/machinery/p2_box/proc/emag_effect(datum/act/op/A)
	emag_ran++
	return OP_OK

/obj/machinery/p2_box/proc/pressed(datum/act/op/A, n)
	pressed_with = n
	return OP_OK

/obj/machinery/p2_box/proc/fit_wait(datum/act/A)
	return fitting_time

/obj/machinery/p2_box/proc/fitted_now(datum/act/op/A)
	fitted++
	return OP_OK

/obj/machinery/p2_box/ui_data(datum/act/eval/A)
	return list("pressed_with" = pressed_with, "viewer" = A.actor ? A.actor.name : null)

/// The same box, listening for a slash.
/obj/machinery/p2_box/slasher
	var/slashed = 0

CAPABILITIES(/obj/machinery/p2_box/slasher, on_notice(/datum/notice/slashed, then(PROC_REF(heard_slash))))

/obj/machinery/p2_box/slasher/proc/heard_slash(datum/act/A)
	slashed++

#endif
