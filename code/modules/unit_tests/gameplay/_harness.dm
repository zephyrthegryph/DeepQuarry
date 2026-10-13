// Gameplay scenarios: end-to-end tests of the core player loops (doc/testing.md "Gameplay scenarios").
//
// Each scenario drives the game the way a player does and asserts what the player would observe. Input goes in the way a client
// sends it: a click is a /datum/input_event/click through input_submit() (the player path, not the driver's resolver shortcut), a
// window button is test_ui() (the same op_ui_act() a tgui window reaches), a right-click pick is test_menu(), a step is the mob
// move a client's Move() makes, a hotkey is the verb its macro runs. Time is the kernel's own (test_driver_begin()/test_time()).
// Assertions read outcomes (a door's density, what is drawn on the mob, the toxin in the blood, the window's data), never snapshots.
//
// A scenario that fails because of a bug in another lane's scope sets `expected_failure` to the reason: it still runs, a failure is
// reported as a notice ("EXPECTED FAILURE"), and a pass fails the test so the marker is removed once the bug is fixed.
//
// The whole suite runs on every lane landing (tools/dq_lane_ready.sh reads tools/ci/gameplay_tests.txt). Keep each scenario short.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_gameplay
	abstract_type = /datum/unit_test/dq_gameplay
	/// Why this scenario is known to fail (another lane's bug), or null. See the header.
	var/expected_failure
	/// The player the scenario made last (spawn_player()).
	var/mob/living/carbon/human/player

/datum/unit_test/dq_gameplay/New()
	..()
	// Visibility queries share a persistent cache: warm it before the runner snapshots globals, so a scenario leaves no lazy-init warning.
	dview(0, test_floor())

/datum/unit_test/dq_gameplay/Run()
	var/started = REALTIMEOFDAY
	test_driver_begin()
	set_global(nameof(GLOB.test_prompts), list())
	test_prompts_reset()
	try
		play()
	catch(var/exception/e)
		Fail("runtime in the scenario: [e] ([e.file]:[e.line])", e.file, e.line)
	cancel_open_prompts()
	test_driver_end()
	log_world("gameplay [type]: [(REALTIMEOFDAY - started) / 10] s")
	settle_expected_failure()

/// The scenario itself.
/datum/unit_test/dq_gameplay/proc/play()
	return

/// A scenario marked expected_failure: its failure becomes a notice, its pass a failure.
/datum/unit_test/dq_gameplay/proc/settle_expected_failure()
	if(!expected_failure)
		return
	if(succeeded)
		Fail("marked expected_failure ([expected_failure]) but it passed: remove the marker", __FILE__, __LINE__)
		return
	var/list/reasons = list()
	for(var/list/reason as anything in fail_reasons)
		reasons += reason[1]
	succeeded = TRUE
	fail_reasons = null
	TEST_NOTICE(src, "EXPECTED FAILURE ([expected_failure]): [jointext(reasons, " | ")]")

/// Closes every prompt the scenario left open, so no request outlives it.
/datum/unit_test/dq_gameplay/proc/cancel_open_prompts()
	for(var/datum/prompt/P as anything in GLOB.test_prompts)
		if(istype(P) && P.is_open())
			test_prompt_answer(P, null, TRUE)

// ---------------------------------------------------------------------------------------------------------------------
// The world
// ---------------------------------------------------------------------------------------------------------------------

/// A floor of the 5x5 test room, `dx` and `dy` from its bottom-left corner (the room's walls are at -1 and 5).
/datum/unit_test/dq_gameplay/proc/tile(dx, dy)
	return locate(run_loc_floor_bottom_left.x + dx, run_loc_floor_bottom_left.y + dy, run_loc_floor_bottom_left.z)

/// Lets `seconds` of kernel time pass, a second at a time, delivering the change reactions after each (life_test_advance()). The
/// injected clock does not step the live world services, so each second also runs, when asked, the native gas frame and its watches
/// (`gas`) and a power step (`power`), as the live kernel would in that second.
/datum/unit_test/dq_gameplay/proc/pass_time(seconds = 1, gas = FALSE, power = FALSE)
	var/left = seconds
	while(left > 0)
		var/step = min(left, 1)
		if(gas)
			dq_gas_level_test_deliver()
		if(power)
			dq_power_test_step()
		test_time(step * 10)
		rx_drain()
		left -= step
	refresh_flush()

// ---------------------------------------------------------------------------------------------------------------------
// The player
// ---------------------------------------------------------------------------------------------------------------------

/// A human as a joining player has one: a body someone controls (so its Life does not put it to sleep as SSD), a HUD, and with
/// `dressed` a jumpsuit and shoes. With `access` it wears an ID holding that access.
/datum/unit_test/dq_gameplay/proc/spawn_player(turf/where, list/access, dressed = TRUE, species = null)
	var/mob/living/carbon/human/H = species ? allocate(/mob/living/carbon/human, where || tile(1, 1), species) : allocate(/mob/living/carbon/human, where || tile(1, 1))
	possess(H)
	if(dressed)
		H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
		H.equip_to_slot_or_del(new /obj/item/clothing/shoes/black(H), SLOT_ID_SHOES)
	if(access)
		var/obj/item/card/id/card = new(H)
		card.set_access(access)
		card.set_registered_name("Gameplay Tester")
		H.equip_to_slot_or_del(card, SLOT_ID_ID)
	refresh_flush()
	player = H
	return H

/// Gives `H` what a connected client gives a body: someone controlling it, a HUD, and a place in the Life sequence.
/datum/unit_test/dq_gameplay/proc/possess(mob/living/carbon/human/H)
	var/mob/controller = allocate(/mob/living/simple_mob/e0_fixture, tile(4, 4))
	controller.invisibility = INVISIBILITY_MAXIMUM
	controller.density = FALSE
	rel_set(H, nameof(H.teleop), controller)
	if(!H.hud_used)
		H.set_hud_used(new /datum/hud(H))
		H.hud_used.instantiate()
	life_test_place(H)

/// The player clicks `target` with whatever is in the active hand (`params` as the mouse parameters), and a moment for it to play out.
/// A map atom's click is what /atom/Click() makes of a client's click: a click event through the input inbox; the result is what the
/// inbox resolved (null when the legacy path took it). A HUD object's click is its native Click() with the player as usr, as BYOND calls it.
/datum/unit_test/dq_gameplay/proc/click(mob/living/H, atom/target, params = "left=1", wait = 1)
	cooldown_set_end(H, next_click, 0)
	. = null
	if(istype(target, /atom/movable/screen))
		with_actor(H, target, "Click", null, "mapwindow.map", params)
	else
		var/datum/input_event/click/E = new(H, target, isturf(target) ? target : target.loc, "mapwindow.map", params)
		input_submit(E)
		. = E.result
	if(wait)
		pass_time(wait)

/// The player presses a button of `host`'s window, as the tgui window sends it. Returns the op's result.
/datum/unit_test/dq_gameplay/proc/press(mob/living/H, datum/host, action, list/arguments, wait = 1)
	var/datum/op_result/result = test_ui(H, host, action, arguments || list())
	if(wait)
		pass_time(wait)
	return result

/// The player picks the line `op_key` of `target`'s right-click menu. Returns the op's result.
/datum/unit_test/dq_gameplay/proc/menu_pick(mob/living/H, atom/target, op_key, wait = 1)
	var/datum/op_result/result = test_menu(H, target, op_key)
	if(wait)
		pass_time(wait)
	return result

/// The lines of the right-click menu the player sees on `target`: list(list("id", "name", "enabled")), available ones first.
/datum/unit_test/dq_gameplay/proc/menu_lines(mob/living/H, atom/target)
	var/list/data = interaction_menu_data(H, target)
	. = list()
	for(var/list/entry as anything in data["available"])
		. += list(list("id" = entry["id"], "name" = entry["name"], "enabled" = TRUE))
	for(var/list/entry as anything in data["blocked"])
		. += list(list("id" = entry["id"], "name" = entry["name"], "enabled" = FALSE))

/// One step in `dir`, as a client's Move() makes it (the cooldown it waits out is skipped, as a held key would wait it out). Walking
/// into a door bumps it. Returns TRUE when the player moved.
/datum/unit_test/dq_gameplay/proc/stride(mob/living/H, dir)
	cooldown_set_end(H, next_move, 0)
	if(!H.canmove || H.stat != CONSCIOUS || !isturf(H.loc))
		return FALSE
	var/turf/from = H.loc
	var/turf/ahead = get_step(H, dir)
	H.SelfMove(ahead, dir, H.movement_delay(ahead, dir))
	pass_time(1)
	return H.loc != from

/// The hotkey E (quick equip): what is in the active hand goes on.
/datum/unit_test/dq_gameplay/proc/key_equip(mob/living/carbon/human/H)
	H.quick_equip()
	pass_time(1)

/// The hotkey Q (drop), as /client/verb/drop_item() runs it.
/datum/unit_test/dq_gameplay/proc/key_drop(mob/living/H)
	if(H.stat == CONSCIOUS && isturf(H.loc))
		H.drop_item()
	pass_time(1)

/// The player's HUD slot showing `slot_id` (a screen object a click on takes the item off or puts the held one on).
/datum/unit_test/dq_gameplay/proc/hud_slot(mob/living/H, slot_id)
	for(var/atom/movable/screen/inventory/S in H.hud_used?.adding + H.hud_used?.other + H.hud_used?.hotkeybuttons)
		if(S.slot_id == slot_id)
			return S
	return null

/// TRUE when one of `A`'s drawn overlays uses `drawn` as its icon.
/datum/unit_test/dq_gameplay/proc/draws_icon(atom/A, drawn)
	for(var/overlay in A.overlays)
		var/mutable_appearance/MA = new(overlay)
		if(MA.icon == drawn)
			return TRUE
	return FALSE

/// The layers of `A`'s drawn overlays, as a list of numbers (what the client sorts them by).
/datum/unit_test/dq_gameplay/proc/drawn_layers(atom/A)
	. = list()
	for(var/overlay in A.overlays)
		var/mutable_appearance/MA = new(overlay)
		. += MA.layer

/// The plain texts sent to the player's chat since the scenario began.
/datum/unit_test/dq_gameplay/proc/chat(mob/living/H)
	return test_chat_of(H)

/// A wall of the test room next to floor tile (`dx`, `dy`), with the floor beside it: list(wall, floor).
/datum/unit_test/dq_gameplay/proc/room_wall()
	var/turf/floor = tile(0, 2)
	var/turf/simulated/wall/W = get_step(floor, WEST)
	if(!istype(W))
		return null
	return list(W, floor)

#endif
