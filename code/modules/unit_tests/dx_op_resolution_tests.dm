// Gesture resolution on the op model (doc/rewrite/operations_and_actions.md §5): the bind profile's action list in the
// actor's stance, then op priority, then declaration order; ACT_NONE ops reached only by key or name; the stance as a
// gesture modifier (ACT_ATTACK); ROUTE_TK with the telekinesis affordance as provider; the silicon interface and the
// observer route; and the library's capabilities building nothing but real ops (G16).

/// Ops that compete for one click, one menu-only op, attacks and a grab: each handler logs its key.
/obj/cap_fixture/resolve
	name = "resolution fixture"
	var/list/ran

/obj/cap_fixture/resolve/capabilities()
	. = ..()
	// Declared first at the default priority: loses to "high" by priority, beats "tied" by declaration order.
	. += cap_op("Low", PROC_REF(fx_low), key = "low")
	. += cap_op("High", PROC_REF(fx_high), key = "high", priority = OP_PRIORITY_PART, needs = req_clear(CAP_LOCKED))
	. += cap_op("Tied", PROC_REF(fx_tied), key = "tied")
	// ACT_LOCK comes after ACT_USE in the click's action list: no op priority lifts it over the ACT_USE ops.
	. += cap_op("Lock first", PROC_REF(fx_lock), key = "lock_first", action = ACT_LOCK, priority = 100)
	// No gesture reaches it; a window may run it too (ROUTE_UI), and the command bar over the actor's own route.
	. += cap_op("Menu only", PROC_REF(fx_menu), key = "menu_only", action = ACT_NONE, via = ROUTE_PHYSICAL | ROUTE_UI)
	. += cap_op("Hands only", PROC_REF(fx_menu), key = "hands_only", action = ACT_NONE)
	. += cap_op("Strike", PROC_REF(fx_strike), key = "strike", action = ACT_ATTACK)
	. += cap_op("Shove", PROC_REF(fx_shove), key = "shove", action = ACT_ATTACK, stance = list(I_DISARM), priority = 5)
	. += cap_op("Grab it", PROC_REF(fx_grab), key = "grab_it", stance = I_GRAB, priority = 50)

/obj/cap_fixture/resolve/proc/fx_low(mob/user)
	LAZYADD(ran, "low")
	return TRUE

/obj/cap_fixture/resolve/proc/fx_high(mob/user)
	LAZYADD(ran, "high")
	return TRUE

/obj/cap_fixture/resolve/proc/fx_tied(mob/user)
	LAZYADD(ran, "tied")
	return TRUE

/obj/cap_fixture/resolve/proc/fx_lock(mob/user)
	LAZYADD(ran, "lock_first")
	return TRUE

/obj/cap_fixture/resolve/proc/fx_menu(mob/user)
	LAZYADD(ran, "menu_only")
	return TRUE

/obj/cap_fixture/resolve/proc/fx_strike(mob/user)
	LAZYADD(ran, "strike")
	return TRUE

/obj/cap_fixture/resolve/proc/fx_shove(mob/user)
	LAZYADD(ran, "shove")
	return TRUE

/obj/cap_fixture/resolve/proc/fx_grab(mob/user)
	LAZYADD(ran, "grab_it")
	return TRUE

/// The key of the op a gesture reaches for `user` on `A`, or null.
/proc/dx_resolved_key(mob/user, atom/A, gesture)
	var/list/resolved = resolve_gesture(user, A, gesture, null, ROUTE_PHYSICAL, TRUE, TRUE)
	if(!resolved)
		return null
	var/datum/interaction/capability/E = resolved[2]
	return E.op?.key

/// The profile's action list, then op priority, then declaration order; a refused op yields to a runnable one of its action.
/datum/unit_test/dx_op_resolution_order/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/resolve/F = allocate(/obj/cap_fixture/resolve, T)
	H.set_use_stance(I_HELP)

	var/list/keys = list()
	for(var/datum/interaction/capability/E as anything in action_entries(F, ACT_USE, TRUE))
		keys += E.op.key
	TEST_ASSERT_EQUAL(jointext(keys, ","), "grab_it,high,low,tied", "an action's ops sort by priority, then declaration order")

	var/list/resolved = resolve_gesture(H, F, GESTURE_CLICK, null, ROUTE_PHYSICAL, TRUE, TRUE)
	TEST_ASSERT_EQUAL(resolved?[1], ACT_USE, "the profile's first action for a click (ACT_USE) is reached before ACT_LOCK, whatever the lock op's priority")
	TEST_ASSERT_EQUAL(dx_resolved_key(H, F, GESTURE_CLICK), "high", "the higher priority op beats the one declared first")
	cap_set(F, CAP_LOCKED, TRUE)
	TEST_ASSERT_EQUAL(dx_resolved_key(H, F, GESTURE_CLICK), "low", "a refused op yields to the next that would run; equal priorities go by declaration order")
	cap_set(F, CAP_LOCKED, FALSE)

	TEST_ASSERT_EQUAL(try_interaction(H, F, null, INPUT_ACTION_USE, null, TRUE), INTERACTION_TRY_RAN, "the click ran through the router")
	TEST_ASSERT_EQUAL(jointext(F.ran, ","), "high", "the op it reached")

	// What the gesture does not reach stays in the radial, named by key.
	var/list/rows = list()
	for(var/list/row as anything in action_options(H, F))
		rows[row["id"]] = row
	for(var/key in list("low", "high", "tied", "lock_first", "menu_only", "strike", "shove", "grab_it"))
		TEST_ASSERT(rows[key], "the radial lists [key]")
	TEST_ASSERT_EQUAL(rows["menu_only"]?["action"], ACT_NONE, "an ACT_NONE op is a radial row with no action")

/// ACT_NONE: no gesture reaches it; its key or name does, from the command bar, the UI route and perform_op().
/datum/unit_test/dx_op_act_none/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/resolve/F = allocate(/obj/cap_fixture/resolve, T)
	H.set_use_stance(I_HELP)
	var/datum/interaction/capability/menu = op_entry_named(H, F, "menu_only")
	TEST_ASSERT_NOTNULL(menu, "op_entry_named() finds an op by key")
	TEST_ASSERT_EQUAL(op_entry_named(H, F, "Menu only"), menu, "and by name, any case")
	TEST_ASSERT_EQUAL(op_entry_named(H, F, "menu-only"), menu, "and by key with hyphens")
	TEST_ASSERT_NULL(menu.default_action, "the resolver answers no input with it either")
	TEST_ASSERT_NULL(action_def_of(ACT_NONE), "ACT_NONE is no action")
	for(var/gesture in list(GESTURE_CLICK, GESTURE_SELF, GESTURE_ALT, GESTURE_CTRL, GESTURE_SHIFT, GESTURE_DRAG, GESTURE_RIGHT))
		for(var/stance in list(I_HELP, I_DISARM, I_GRAB, I_HURT))
			TEST_ASSERT(!(ACT_NONE in bind_profile_of(H).actions_for(gesture, stance)), "no profile lists ACT_NONE ([gesture], [stance])")
		TEST_ASSERT_NOTEQUAL(dx_resolved_key(H, F, gesture), "menu_only", "no gesture reaches it ([gesture])")
	var/datum/interaction_resolution/resolution = interactions_for(H, F, null, null, null, INPUT_ACTION_USE)
	TEST_ASSERT(!(menu in resolution.available), "the resolver's Use leaves it out")

	TEST_ASSERT_NULL(test_op(H, F, "menu_only"), "test_op() says it would run")
	TEST_ASSERT(perform_op(H, F, "menu_only"), "perform_op() runs it by key")
	TEST_ASSERT(command_action(H, "menu only", F), "the command bar runs it by name")
	var/datum/tgui/ui = ui_test_window(F)
	ui.user = H
	TEST_ASSERT(F.tgui_act("action", list("id" = "menu_only"), ui), "the UI route runs it by key")
	TEST_ASSERT_EQUAL(jointext(F.ran, ","), "menu_only,menu_only,menu_only", "each of the three ran it")
	TEST_ASSERT(!command_action(H, "no such op", F), "a name nothing answers is refused")
	TEST_ASSERT(!F.tgui_act("action", list("id" = "hands_only"), ui), "an op that does not take ROUTE_UI is not a window's")
	TEST_ASSERT(command_action(H, "hands_only", F), "but the command bar runs it over the actor's own route")

/// The stance is a gesture modifier: harm and disarm click ACT_ATTACK before ACT_USE; help and grab never reach an attack.
/datum/unit_test/dx_op_stance_gesture/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/resolve/F = allocate(/obj/cap_fixture/resolve, T)
	var/datum/bind_profile/profile = bind_profile_of(H)
	var/list/harm = profile.actions_for(GESTURE_CLICK, I_HURT)
	TEST_ASSERT_EQUAL(harm[1], ACT_ATTACK, "harm clicks ACT_ATTACK first")
	TEST_ASSERT(harm.Find(ACT_USE) == 2, "then ACT_USE")
	TEST_ASSERT(ACT_ATTACK in profile.actions_for(GESTURE_CLICK, I_DISARM), "disarm is hostile too")
	TEST_ASSERT(!(ACT_ATTACK in profile.actions_for(GESTURE_CLICK, I_HELP)), "help never reaches an attack")
	TEST_ASSERT(!(ACT_ATTACK in profile.actions_for(GESTURE_CLICK, I_GRAB)), "nor does grab")
	TEST_ASSERT_EQUAL(profile.actions_for(GESTURE_CLICK, I_HELP)[1], ACT_USE, "help clicks ACT_USE")
	TEST_ASSERT(!(ACT_ATTACK in profile.actions_for(GESTURE_ALT, I_HURT)), "a gesture the stance lists nothing for keeps its own list")

	H.set_use_stance(I_HURT)
	TEST_ASSERT_EQUAL(dx_resolved_key(H, F, GESTURE_CLICK), "strike", "harm reaches the attack op (the disarm-only shove is not meant)")
	H.set_use_stance(I_DISARM)
	TEST_ASSERT_EQUAL(dx_resolved_key(H, F, GESTURE_CLICK), "shove", "disarm reaches the disarm attack, by its priority")
	H.set_use_stance(I_GRAB)
	TEST_ASSERT_EQUAL(dx_resolved_key(H, F, GESTURE_CLICK), "grab_it", "grab reaches the grab-only use")
	H.set_use_stance(I_HELP)
	TEST_ASSERT_EQUAL(dx_resolved_key(H, F, GESTURE_CLICK), "high", "help reaches the plain use")
	var/datum/interaction/capability/shove = op_entry_named(H, F, "shove")
	TEST_ASSERT(!shove.is_meant(H, F, null), "a stance list is an offered requirement: not meant in help")
	TEST_ASSERT_EQUAL(req_stance(list(I_DISARM)), req_stance(I_DISARM), "one stance and a list of it are one flyweight")
	H.set_use_stance(I_DISARM)
	TEST_ASSERT(shove.is_meant(H, F, null), "meant in disarm")
	H.set_use_stance(I_HELP)

/// A telekinetic reach at range: ROUTE_TK, with the telekinesis affordance as its provider.
/obj/cap_fixture/tk_target
	name = "telekinesis target"
	anchored = FALSE
	var/list/ran

/obj/cap_fixture/tk_target/capabilities()
	. = ..()
	// A hand's op, declared first: a telekinetic click is not a request for it (routed), and passes it over.
	. += cap_op("Touch", PROC_REF(fx_touch), key = "touch")
	. += cap_op("Nudge", PROC_REF(fx_nudge), key = "nudge", via = ROUTE_PHYSICAL | ROUTE_TK)

/obj/cap_fixture/tk_target/proc/fx_touch(mob/user)
	LAZYADD(ran, "touch")
	return TRUE

/obj/cap_fixture/tk_target/proc/fx_nudge(mob/user)
	LAZYADD(ran, "nudge")
	return TRUE

/datum/unit_test/dx_op_route_tk/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/away = locate(T.x + 3, T.y, T.z)
	TEST_ASSERT_NOTNULL(away, "a turf three tiles away")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/tk_target/F = allocate(/obj/cap_fixture/tk_target, away)
	var/datum/input_adapter/telekinesis/tk = INPUT_ADAPTER(telekinesis)
	TEST_ASSERT_EQUAL(tk.op_route(H, null), ROUTE_TK, "a telekinetic click travels ROUTE_TK")
	var/datum/input_adapter/hands = H.input_adapter()
	TEST_ASSERT_EQUAL(hands.op_route(H, null), ROUTE_PHYSICAL, "a hand's click does not")
	var/datum/interaction/capability/nudge = op_entry_named(H, F, "nudge")

	// Without the affordance: the op is still what the click means, and the provider stage refuses it.
	var/datum/op_ctx/ctx = op_ctx_take(H, F, null, nudge.op, ROUTE_TK)
	TEST_ASSERT_EQUAL(ctx.check(), /datum/msg/req_no_provider, "no telekinesis, no provider")
	TEST_ASSERT_EQUAL(ctx.failed_stage, OP_STAGE_PROVIDER, "at the provider stage")
	H.add_mutation(TK)
	TEST_ASSERT(H.has_telegrip(), "the mutation gives the telekinesis affordance")
	TEST_ASSERT_NULL(ctx.check(), "with it the op passes over the tk route at range")
	ctx.release()

	TEST_ASSERT_EQUAL(gesture_entry_for(H, F, null, GESTURE_CLICK, null, FALSE, tk), nudge, "the telekinetic click reaches the op that takes ROUTE_TK, passing over the hand's op")
	TEST_ASSERT_EQUAL(try_interaction(H, F, null, INPUT_ACTION_USE, null, TRUE, tk), INTERACTION_TRY_RAN, "and runs it")
	TEST_ASSERT_EQUAL(jointext(F.ran, ","), "nudge", "the tk op ran, not the hand's")

	// Out of reach: another place entirely.
	F.moveToNullspace()
	ctx = op_ctx_take(H, F, null, nudge.op, ROUTE_TK)
	TEST_ASSERT_EQUAL(ctx.check(), /datum/msg/req_out_of_reach, "nothing to reach out to")
	ctx.release()
	F.forceMove(away)
	H.remove_mutation(TK)

/// A silicon works a control through its interface: its interface is the provider over ROUTE_INTERFACE.
/datum/unit_test/dx_op_silicon_interface/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/cap_fixture/ops/F = allocate(/obj/cap_fixture/ops, T)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	var/datum/op_def/console = dx_op_of(F, "console")
	var/datum/op_ctx/ctx = op_ctx_take(R, F, null, console, ROUTE_INTERFACE)
	TEST_ASSERT_NULL(ctx.check(OP_STAGE_PROVIDER), "the silicon's interface provides AFF_CONTROL over the interface route")
	ctx.release()
	ctx = op_ctx_take(R, F, null, console, ROUTE_PHYSICAL)
	TEST_ASSERT_EQUAL(ctx.check(OP_STAGE_PROVIDER), /datum/msg/req_no_provider, "but no hand for the physical route")
	ctx.release()

/// An observer's click travels ROUTE_UI and reaches an ACT_EXAMINE op there: the old observer entry.
/obj/cap_fixture/observed
	name = "observed fixture"
	var/list/ran

/obj/cap_fixture/observed/capabilities()
	. = ..()
	. += cap_op("Peek", PROC_REF(fx_peek), key = "peek", action = ACT_EXAMINE, via = ROUTE_UI, by = NONE)

/obj/cap_fixture/observed/proc/fx_peek(mob/user)
	LAZYADD(ran, "peek")
	return TRUE

/datum/unit_test/dx_op_observer_route/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/observed/F = allocate(/obj/cap_fixture/observed, T)
	TEST_ASSERT_EQUAL(ghost.op_route(null), ROUTE_UI, "an observer reaches through a window")
	var/datum/interaction/capability/peek = op_entry_named(ghost, F, "peek")
	TEST_ASSERT_EQUAL(gesture_entry_for(ghost, F, null, GESTURE_CLICK), peek, "a ghost's click reaches the observer op")
	TEST_ASSERT_EQUAL(try_interaction(ghost, F, null, INPUT_ACTION_USE, null, TRUE), INTERACTION_TRY_RAN, "and runs it")
	TEST_ASSERT_EQUAL(jointext(F.ran, ","), "peek", "the observer op ran")
	TEST_ASSERT_NULL(gesture_entry_for(H, F, null, GESTURE_CLICK), "a hand's click does not reach it")

// The former dx_cap_library_ops sweep covered retired leaf-library builders.
// Core gesture/resolution regression groups above and below remain live.

/proc/dx_gesture_key(mob/user, atom/A, obj/item/held)
	var/datum/interaction/capability/E = gesture_entry_for(user, A, held, GESTURE_CLICK)
	if(E)
		return E.op?.key
	var/datum/op_resolution/R = op_resolve(user, A, held, ORIGIN_CLICK, actor_authority(user), GESTURE_CLICK, null, TRUE)
	return op_resolution_winner(R)?.oplan?.key

/// The three files converted as worked examples of the old interaction-spec mapping (operations_and_actions.md §5): an item's USE
/// and VERBs (the megaphone), a machine's ITEM, HAND and VERB (the medical records console) and the stance shapes (the
/// desk bell).
/datum/unit_test/dx_op_converted_examples/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.set_use_stance(I_HELP)

	var/obj/item/megaphone/super/giga = allocate(/obj/item/megaphone/super, T)
	var/datum/op_resolution/self_use = op_resolve(H, giga, giga, ORIGIN_CLICK, actor_authority(H), GESTURE_SELF, null, TRUE)
	TEST_ASSERT_EQUAL(op_resolution_winner(self_use)?.oplan?.key, "shout", "the old self-use entry became a real self-use op")
	TEST_ASSERT_NOTEQUAL(dx_gesture_key(H, giga, null), "shout", "a click on the megaphone never means it")
	var/list/volume_row
	for(var/list/row as anything in op_menu(H, giga, null))
		if(row["key"] == "change_volume")
			volume_row = row
	TEST_ASSERT(volume_row, "the old verb entry is a menu op")
	TEST_ASSERT(!volume_row["enabled"], "only while carried")

	var/obj/machinery/computer/med_data/records = allocate(/obj/machinery/computer/med_data, T)
	var/obj/item/card/id/card = allocate(/obj/item/card/id, T)
	TEST_ASSERT_EQUAL(dx_gesture_key(H, records, null), "open_records", "the old hand entry became the empty hand's op")
	TEST_ASSERT(H.put_in_active_hand(card), "the human holds an ID card")
	TEST_ASSERT_EQUAL(dx_gesture_key(H, records, card), "insert_scan", "the old item entry became the ID slot's insert op")
	TEST_ASSERT_EQUAL(try_interaction(H, records, card, INPUT_ACTION_USE, null, TRUE), INTERACTION_TRY_RAN, "a click with the card ran it")
	TEST_ASSERT_EQUAL(records.scan, card, "the card is in the slot")
	var/datum/interaction/capability/eject = op_entry_named(H, records, "Eject ID Card")
	TEST_ASSERT_EQUAL(eject?.op?.action, ACT_NONE, "the old verb entry became the slot's ACT_NONE eject")
	TEST_ASSERT(perform_op(H, records, "Eject ID Card"), "the Menu's eject runs by name")
	TEST_ASSERT_NULL(records.scan, "the card came out")
	TEST_ASSERT(H.is_in_hands(card), "into the hand")

	var/obj/item/deskbell/bell = allocate(/obj/item/deskbell, T)
	H.drop_from_inventory(card)
	TEST_ASSERT_EQUAL(dx_gesture_key(H, bell, null), "ring", "a help touch rings")
	H.set_use_stance(I_DISARM)
	TEST_ASSERT_EQUAL(dx_gesture_key(H, bell, null), "ring", "so does a disarm touch: the harm-only attack is not meant")
	H.set_use_stance(I_HURT)
	TEST_ASSERT_EQUAL(dx_gesture_key(H, bell, null), "hammer", "a harm touch reaches the ACT_ATTACK op")
	TEST_ASSERT(H.put_in_active_hand(card), "the human holds the card again")
	TEST_ASSERT_EQUAL(dx_gesture_key(H, bell, card), "hammer_with_item", "and so does an item in harm")
	H.set_use_stance(I_HELP)
	TEST_ASSERT_EQUAL(dx_gesture_key(H, bell, card), "ring_with_item", "an item in help rings")
