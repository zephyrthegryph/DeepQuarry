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

CAPABILITIES(/obj/p2_hit/taker)
	extend(/datum/act/hit/emp, instead(then(PROC_REF(take_over))))

/obj/p2_hit/taker/proc/take_over(datum/act/A)
	took++

/// Halves every hit through the generic hit, and refuses fire.
/obj/p2_hit/halver

CAPABILITIES(/obj/p2_hit/halver)
	extend(/datum/act/hit, adjusts("packet.amounts", scale = 0.5))
	extend(/datum/act/hit/fire, needs(req(PROC_REF(never), because = MSG(p1/not_ready))))

/obj/p2_hit/halver/proc/never(datum/act/A)
	return FALSE

/// Hears a blob hit after it landed.
/obj/p2_hit/listener

CAPABILITIES(/obj/p2_hit/listener)
	on_notice(/datum/notice/hit/blob, then(PROC_REF(hear)))

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

CAPABILITIES(/obj/p2_hit/both)
	extend(/datum/act/hit/emp, adjusts("packet.amounts", scale = 0.5))

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

CAPABILITIES(/obj/p2_frame)
	construction(start(STAGE_DOOR_FRAME),
		stage(STAGE_DOOR_WIRED, stack(/obj/item/stack/cable_coil, 5), undo = null),
		dismantle(tool(TOOL_CROWBAR), wait(0), becomes(/obj/item/p2_frame_item),
			ruined(TYPE_PROC_REF(/obj/p2_frame, frame_ruined), becomes(/obj/item/p2_scrap))))

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
	var/began = 0
	var/label_shown = TRUE

TRACKED(/obj/machinery/p2_box, label_shown)

CAPABILITIES(/obj/machinery/p2_box)
	machine_basics(null, repair = NONE, frame = NONE, powered = FALSE)
	maintenance_hatch( 		cover = cover(open = tool(TOOL_CROWBAR)), 		wires = /datum/wires/p2_box, 		emag = list(then(PROC_REF(emag_effect))), 		panel_needs_cover_closed = TRUE, 		starts_locked = nameof(lock_at_start))
	owns_one(nameof(cell), /obj/item/cell, on_destroy = ON_DESTROY_SPILL)
	cell_bay(nameof(cell), at = BAY_HATCH)
	interface("P2Box")
	look_layer("p2-label", when = nameof(label_shown))
	examine_line(MSG(p2/ui_forbidden), when = cond_not(nameof(label_shown)))
	op("press", ui_act(arg("n", int(0, 9))), then(PROC_REF(pressed)))
	op("fit", tool(TOOL_WRENCH), wait(PROC_REF(fit_wait)), begins(PROC_REF(fit_begins)), then(PROC_REF(fitted_now)))

/obj/machinery/p2_box/proc/emag_effect(datum/act/op/A)
	emag_ran++
	return OP_OK

/obj/machinery/p2_box/proc/pressed(datum/act/op/A, n)
	pressed_with = n
	return OP_OK

/obj/machinery/p2_box/proc/fit_wait(datum/act/A)
	return fitting_time

/// begins(): told when the wait starts (a fixture counts it; it tells nobody).
/obj/machinery/p2_box/proc/fit_begins(datum/act/A)
	began++
	return null

/obj/machinery/p2_box/proc/fitted_now(datum/act/op/A)
	fitted++
	return OP_OK

/obj/machinery/p2_box/ui_data(datum/act/eval/A)
	return list("pressed_with" = pressed_with, "viewer" = A.actor ? A.actor.name : null)

// ---- legacy entries beside ops ----

/// A target with legacy entry interactions only: a touch with an empty hand, and a held item used on it. Each counts that it ran.
/obj/p2_legacy_target
	name = "p2 legacy target"
	var/touched = 0
	var/used_with = 0

DECLARE_INTERACTIONS(/obj/p2_legacy_target, \
	INTERACT_HAND("Touch", PROC_REF(p2_touched)), \
	INTERACT_ITEM(null, PROC_REF(p2_used)))

/obj/p2_legacy_target/proc/p2_touched(mob/user, obj/item/held, datum/interaction/interaction)
	touched++
	return TRUE

/obj/p2_legacy_target/proc/p2_used(mob/user, obj/item/W, datum/interaction/interaction)
	used_with++
	return TRUE

/// An item with an op of its own (which never applies), so a click with it resolves among the ops and the legacy entries of its target.
/obj/item/p2_op_item
	name = "p2 op item"
	var/tapped = 0

CAPABILITIES(/obj/item/p2_op_item)
	op("p2_idle", at_target(/obj/p2_legacy_target), when(PROC_REF(p2_never)), then(PROC_REF(p2_idle)))
	op("p2_turf", at_target(/turf), priority(OP_PRIORITY_PART), then(PROC_REF(p2_tapped)))

/obj/item/p2_op_item/proc/p2_tapped(datum/act/op/A)
	tapped++
	return OP_OK

/obj/item/p2_op_item/proc/p2_never(datum/act/A)
	return FALSE

/obj/item/p2_op_item/proc/p2_idle(datum/act/op/A)
	return OP_OK

// ---- without() of a bundle ----

/// A bundle that brings a capability of its own (and with it, ops).
CAPABILITY_DEF(p2_bundle, CAP_P2_BUNDLE, key = NONE)

/datum/capability/def/p2_bundle/entries()
	return list(reagent_container(volume = 10))

/obj/p2_bundled
	name = "p2 bundled"

CAPABILITIES(/obj/p2_bundled)
	p2_bundle()

/// The same, without the bundle: nothing it brought stays, the nested capability and its ops included.
/obj/p2_bundled/stripped
	name = "p2 stripped"

CAPABILITIES(/obj/p2_bundled/stripped)
	without(CAP_P2_BUNDLE)

// ---- afterattack on a mob ----

/// An item that does no harm and does its work in afterattack (a spray, a syringe), counting how often it did.
/obj/item/p2_afterattacker
	name = "p2 afterattacker"
	force = 0
	var/reached = 0

/obj/item/p2_afterattacker/afterattack(atom/target, mob/user, proximity_flag, click_parameters, stance = I_HURT)
	reached++
	return

/// The same, but its attack() takes the click (what a beaker feeding somebody does).
/obj/item/p2_afterattacker/attacker

/obj/item/p2_afterattacker/attacker/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	return ITEM_INTERACT_SUCCESS

/// The same box, listening for a slash.
/obj/machinery/p2_box/slasher
	var/slashed = 0

CAPABILITIES(/obj/machinery/p2_box/slasher)
	on_notice(/datum/notice/slashed, then(PROC_REF(heard_slash)))

/obj/machinery/p2_box/slasher/proc/heard_slash(datum/act/A)
	slashed++

// ---- a pinned gesture ----

/// Two ops on one input: an item used on it, and the same item dragged onto it. Both bind item(/obj/item); the drag one pins gesture(GESTURE_DRAG)
/// and says nothing else, so the pin alone must make it answer the drag and keep it from clashing with the use.
/obj/p2_dragtarget
	name = "p2 drag target"
	var/used = 0
	var/dragged = 0
	/// The click parameters the last op ran under (dq_interaction_click_params of its actor).
	var/seen_params

CAPABILITIES(/obj/p2_dragtarget)
	op("use", item(/obj/item), then(PROC_REF(was_used)))
	op("drag", item(/obj/item), gesture(GESTURE_DRAG), then(PROC_REF(was_dragged)))

/obj/p2_dragtarget/proc/was_used(datum/act/op/A)
	used++
	seen_params = dq_interaction_click_params(A.actor)
	return OP_OK

/obj/p2_dragtarget/proc/was_dragged(datum/act/op/A)
	dragged++
	seen_params = dq_interaction_click_params(A.actor)
	return OP_OK


// ---- an asks() with a condition ----

/// A holder whose op asks for a number only while `want` says so.
/obj/p2_asker
	name = "p2 asker"
	var/want = FALSE
	var/ran = 0
	var/asked_value = null

CAPABILITIES(/obj/p2_asker)
	op("ask", ui_act(), asks(/datum/prompt/number, when = PROC_REF(ask_wanted)), then(PROC_REF(asked_done)))

/obj/p2_asker/proc/ask_wanted(datum/act/op/A)
	return want // ALLOW(reads): a test fixture's plain flag, read when the step is reached

/obj/p2_asker/proc/asked_done(datum/act/op/A)
	ran++
	var/datum/prompt/P = A.answer
	asked_value = P?.value
	return OP_OK

// ---- a subtype's own window ----

/// A holder with a window.
/obj/p2_windowed
	name = "p2 windowed"

CAPABILITIES(/obj/p2_windowed)
	interface("P2First")
	op("p2_window_press", ui_act(), then(PROC_REF(window_pressed)))

/obj/p2_windowed/proc/window_pressed(datum/act/op/A)
	return OP_OK

/// A subtype with its own window: the inherited open op goes, the new window is the one it opens.
/obj/p2_windowed/second
	name = "p2 windowed second"

CAPABILITIES(/obj/p2_windowed/second)
	without("ui_open")
	interface("P2Second")
	op("p2_window_press_second", ui_act(), then(PROC_REF(window_pressed)))

#endif
