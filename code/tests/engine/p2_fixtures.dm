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
	extend(/datum/act/hit/fire, needs(req_bool(PROC_REF(never), because = MSG(p1/not_ready))))

/obj/p2_hit/halver/proc/never(datum/act/A)
	return FALSE

/// Hears a blob hit after it landed.
/obj/p2_hit/listener

CAPABILITIES(/obj/p2_hit/listener)
	on_notice(/datum/notice/hit/blob, then(PROC_REF(hear)))

/obj/p2_hit/listener/proc/hear(datum/act/A)
	heard++
	integrity_when_heard = get_integrity()

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
		stage(STAGE_DOOR_WIRED, stack(/obj/item/stack/cable_coil, 5), undo = NO_UNDO),
		dismantle(tool(TOOL_CROWBAR), wait(0), becomes(/obj/item/p2_frame_item),
			ruined(TYPE_PROC_REF(/obj/p2_frame, frame_ruined), becomes(/obj/item/p2_scrap))))

// ---- the machine library: a box with a hatch (code/library/machine, code/library/access, code/engine/present) ----

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
	maintenance_hatch( 		cover = cover(open = tool(TOOL_CROWBAR)), 		wires = wires(name = "p2 box", count = 2, emp = FALSE), 		emag = list(then(PROC_REF(emag_effect))), 		panel_needs_cover_closed = TRUE, 		starts_locked = nameof(lock_at_start))
	// two wires with nothing behind them: the ID scan and the AI control wire
	id_scan()
	ai_control()
	owns_one(nameof(cell), /obj/item/cell, on_destroy = ON_DESTROY_SPILL)
	cell_bay(nameof(cell), at = SPACE_HATCH)
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

// ---- an item op at a turf ----

/// An item with an op of its own, done at a turf.
/obj/item/p2_op_item
	name = "p2 op item"
	var/tapped = 0

CAPABILITIES(/obj/item/p2_op_item)
	op("p2_turf", at_target(/turf), priority(OP_PRIORITY_PART), then(PROC_REF(p2_tapped)))

/obj/item/p2_op_item/proc/p2_tapped(datum/act/op/A)
	tapped++
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


// ---- every() with a PROC_REF interval ----

/// A holder whose every() asks a proc for its gap before each run: the gaps are 2, 4, 2, 4 ... deciseconds.
/obj/p2_pulse
	name = "p2 pulse"
	var/pulses = 0
	var/gaps_asked = 0

CAPABILITIES(/obj/p2_pulse)
	every(PROC_REF(next_gap), then(PROC_REF(pulse)))

/obj/p2_pulse/proc/next_gap(datum/act/A)
	gaps_asked++
	return (gaps_asked % 2) ? 2 : 4

/obj/p2_pulse/proc/pulse(datum/act/A)
	pulses++

#endif

// ---- a silent requirement ----

MSG_DEF_SELF(p2_silent/closed, "It is closed.")

/// A holder whose button is refused by a requirement that tells nobody (an old ui_act_allowed returning FALSE).
/obj/p2_silent
	name = "p2 silent"
	var/open = FALSE
	var/pressed = 0

CAPABILITIES(/obj/p2_silent)
	op("press", ui_act(), needs(req_bool(PROC_REF(is_open), silent = TRUE)), then(PROC_REF(was_pressed)))
	op("press_loud", ui_act(), needs(req_bool(PROC_REF(is_open), because = MSG(p2_silent/closed))), then(PROC_REF(was_pressed)))

/obj/p2_silent/proc/is_open(datum/act/op/A)
	return open // ALLOW(reads): a test fixture's plain flag, read when the press arrives

/obj/p2_silent/proc/was_pressed(datum/act/op/A)
	pressed++
	return OP_OK

// ---- a window on a datum ----

/// A window host that is not an atom (a tgui module, a prompt window, an app): data and a button, no reach.
/datum/p2_panel
	var/pressed = 0

CAPABILITIES(/datum/p2_panel)
	interface("P2Panel")
	op("panel_press", ui_act(), then(PROC_REF(panel_pressed)))

/datum/p2_panel/ui_data(datum/act/eval/A)
	return list("pressed" = pressed, "viewer" = A.actor ? "[A.actor]" : null)

/datum/p2_panel/proc/panel_pressed(datum/act/op/A)
	pressed++
	return OP_OK

// ---- request re-checks ----

/// An item that asks and records what its handler saw.
/obj/item/p2_asker_item
	name = "p2 asker item"
	var/handled = 0
	var/seen_answer = null

/obj/item/p2_asker_item/proc/answered(datum/act/request/A)
	handled++
	seen_answer = A.answer?.value
	return OP_OK

// ---- a machine's hand gate ----

/// A machine with a hand op, one that opts out of the gate, and a plain item with a hand op.
/obj/machinery/p2_hand_machine
	name = "p2 hand machine"
	var/touched = 0
	var/touched_ungated = 0

CAPABILITIES(/obj/machinery/p2_hand_machine)
	op("touch", hand(), then(PROC_REF(was_touched)))

/obj/machinery/p2_hand_machine/proc/was_touched(datum/act/op/A)
	touched++
	return OP_OK

/obj/machinery/p2_hand_machine/proc/was_touched_ungated(datum/act/op/A)
	touched_ungated++
	return OP_OK

/// The same machine whose touch says ungated(): it works unpowered, for an actor who is up.
/obj/machinery/p2_hand_machine/ungated
	name = "p2 hand machine ungated"

CAPABILITIES(/obj/machinery/p2_hand_machine/ungated)
	without("touch")
	op("touch_ungated", hand(), ungated(), then(PROC_REF(was_touched_ungated)))
