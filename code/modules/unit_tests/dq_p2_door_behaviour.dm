// Behaviour-preservation tests for the door domain (code/game/machinery/doors/, the airlock, windoor and firedoor
// assemblies). They pin what a player, an AI or a machine can observe of a door, so they pass unchanged before and after
// the door types move from the legacy capability library onto the engine forms.
//
// Rules the tests keep:
//   - Inputs are public: a player's click (p2_door_click), a window button (p2_door_ui), a mob bumping, an EMP, a held tool
//     or card, the passage of time. A click is the click event a client sends, through the input inbox: it runs the mob's own
//     click handling on a type that has no engine ops yet and the resolver on one that has, so the same test drives both.
//   - State is read through plain vars (density, operating, stat via has_stat(), contents, loc, get_integrity(), req_access,
//     anchored, state, glass...) or through the p2_door_* adapters below. After the conversion ONLY the adapter bodies change.
//   - Nothing is random: no prob() is left to chance (the EMP tests loop until the roll comes up, under test_rng).
//   - A test never asserts message text or a click result's outcome: it asserts the state that results. After every click or
//     window button the test lets time pass (settle()) before it reads state, because a tool action may wait.
//
// Two clocks. Most tests run on the kernel's injected clock (test_time). A door's own deadlines read world.time (the autoclose
// deadline, the bump cooldown), which test_time does not move, so the tests of those run live: `live = TRUE`, real sleeps, and
// fast door timing (the timing wire) to keep them short.
//
// The room a test runs in is 5x5 floor (maps/templates/unit_tests.dmm) with no APC, so a shock from an electrified door never
// lands (electrocute_mob() finds no power source): electrification is pinned as state, not as damage.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters: the one place the legacy accessors are named. Keep each a one-liner (the click and UI ones are the exceptions).
// ---------------------------------------------------------------------------------------------------------------------

/// Whether the door's bolts are down.
/proc/p2_door_bolted(obj/machinery/door/D)
	return is_bolted(D)

/// Whether the door is welded shut.
/proc/p2_door_welded(obj/machinery/door/D)
	return is_welded(D)

/// Whether touching the door would shock now.
/proc/p2_door_electrified(obj/machinery/door/airlock/D)
	return D.electrified

/// Whether the maintenance panel is open.
/proc/p2_door_panel_open(obj/machinery/door/D)
	return panel_is_open(D)

/// Whether the door has been emagged.
/proc/p2_door_emagged(obj/machinery/door/D)
	return D.emagged || is_emagged(D)

/// Whether emergency access is engaged.
/proc/p2_door_emergency(obj/machinery/door/D)
	return emergency_access_on(D)

/// How far an airlock assembly is built: 0 bare, 1 wired, 2 with its electronics in.
/proc/p2_door_assembly_state(obj/structure/door_assembly/A)
	return A.assembly_state()

/// Whether the door has power it can move on (main or backup).
/proc/p2_door_powered(obj/machinery/door/airlock/D)
	return D.power_systems_on()

/// Whether the door's safeties stop it closing on someone.
/proc/p2_door_safeties(obj/machinery/door/D)
	var/obj/machinery/door/airlock/A = D
	return !istype(A) || !!A.safe

/// Sets whether the door closes itself after a wait (the timing wire's switch).
/proc/p2_door_set_autoclose(obj/machinery/door/D, on)
	D.set_autoclose(on)

/// Whether the firedoor is welded shut.
/proc/p2_firedoor_welded(obj/machinery/door/firedoor/D)
	return D.blocked

/// Welds the firedoor shut or frees it, as the welder does.
/proc/p2_firedoor_set_welded(obj/machinery/door/firedoor/D, on)
	D.set_blocked(on)

/// Whether a firedoor assembly is wired.
/proc/p2_firedoor_assembly_wired(obj/structure/firedoor_assembly/F)
	return built(F, STAGE_FIREDOOR_ASSEMBLY_WIRED)

/// Whether the firedoor's maintenance hatch is open.
/proc/p2_firedoor_hatch_open(obj/machinery/door/firedoor/D)
	return D.hatch_open

/// Cuts wire `wire`, or mends it when it is cut (the wirecutter toggle).
/proc/p2_door_wire_cut(obj/machinery/door/D, wire, mob/actor)
	return wires_toggle(D, wire, actor)

/// Sends a multitool pulse down wire `wire`.
/proc/p2_door_wire_pulse(obj/machinery/door/D, wire, mob/actor)
	return wires_pulse(D, wire, actor)

/// Drops (on) or raises the bolts the way a wire or a button does: forced, no power or wire check.
/proc/p2_door_set_bolts(obj/machinery/door/D, on)
	return set_bolted(D, on, TRUE)

/// Welds the door shut or frees it, as a construct's spell or a mech clamp does.
/proc/p2_door_set_welded(obj/machinery/door/D, on)
	return set_welded(D, on)

/// Puts the machine on (or takes it off) area power.
/proc/p2_door_set_power(obj/machinery/D, on)
	D.set_powered(on)

/// Sets (on) or clears the area's fire alarm: its firedoors close or open.
/proc/p2_area_fire(area/A, on)
	if(on)
		A.fire_alert()
	else
		A.fire_reset()

/// The text of the door's examine.
/proc/p2_door_examine(obj/machinery/door/D, mob/viewer)
	return jointext(D.examine(viewer), "\n")

/// A player's click on `target`, with `held` (when given) in the active hand: the click event a client sends, through the input
/// inbox. Returns what the engine reported, null on a type the engine does not run yet.
/proc/p2_door_click(mob/living/actor, atom/target, obj/item/held)
	if(held && actor.get_active_hand() != held)
		if(actor.get_active_hand())
			actor.drop_item()
		actor.put_in_active_hand(held)
	else if(!held && actor.get_active_hand())
		actor.drop_item()
	actor.next_click = 0
	var/datum/input_event/click/E = new(actor, target, null, "mapwindow.map", "left=1")
	input_submit(E)
	return E.result

/// A window button, as a player presses it. The engine path answers first; a type not yet on it answers through its window.
/proc/p2_door_ui(mob/actor, datum/host, action, list/args)
	var/datum/op_result/result = test_ui(actor, host, action, args || list())
	if(!isnull(result))
		return result
	var/datum/tgui/ui = new(null, host, "UiTest")
	ui.status = STATUS_INTERACTIVE
	ui.user = actor
	return host.tgui_act(action, args || list(), ui)

/// Lets the prompts a type asks the legacy way be answered by the test (they are collected instead of shown). Call once the kernel
/// is on its test clock.
/proc/p2_door_capture_prompts()
	om_scheduler().test_prompts = list()

/// Answers the question `actor` was asked (TRUE: yes, FALSE: no, `cancel`: closes it). The engine's request answers first; a question
/// asked the legacy way is answered through its collected prompt.
/proc/p2_door_answer(mob/actor, value, cancel = FALSE)
	var/datum/op_result/result = test_answer(actor, value, cancel ? REQ_CANCELLED : REQ_ANSWERED)
	if(!isnull(result))
		return result
	var/list/prompts = om_scheduler().test_prompts
	for(var/i in length(prompts) to 1 step -1)
		var/datum/om/prompt/P = prompts[i]
		if(!P.answered && P.peek("answerer") == actor)
			var/answer = value ? "Yes" : "No"
			if(istype(P, /datum/om/prompt/confirm))
				var/datum/om/prompt/confirm/C = P
				answer = value ? C.yes_text : C.no_text
			return om_prompt_answer(P, cancel ? null : answer, cancel)
	return null

/// Time for a click or a window button to play out: far longer than any tool action, shorter than a door's own autoclose.
/proc/p2_door_settle()
	test_time(10 SECONDS)

// ---------------------------------------------------------------------------------------------------------------------
// Fixture types: doors and buttons with a known id, so keyed relations find each other.
// ---------------------------------------------------------------------------------------------------------------------

/obj/machinery/door/blast/regular/p2_test
	id = "p2_blast_test"

/obj/machinery/button/remote/blast_door/p2_test
	id = "p2_blast_test"

/obj/machinery/door/airlock/p2_test
	id_tag = "p2_airlock_test"

/obj/machinery/button/remote/airlock/p2_test
	id = "p2_airlock_test"

/obj/machinery/button/remote/blast_door/single_use/p2_test
	id = "p2_blast_test"

/obj/machinery/button/remote/driver/p2_test
	id = "p2_blast_test"

/obj/machinery/door/window/brigdoor/p2_test
	id = "p2_cell"

/obj/machinery/door_timer/p2_test
	id = "p2_cell"

// ---------------------------------------------------------------------------------------------------------------------
// Base: the kernel on its injected clock around the test (unless the test runs live), a clean driver after.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door
	abstract_type = /datum/unit_test/dq_p2_door
	/// TRUE: real time and the live kernel (a door deadline that reads world.time).
	var/live = FALSE

/datum/unit_test/dq_p2_door/Run()
	if(!live)
		test_driver_begin()
		p2_door_capture_prompts()
	run_gate()
	if(!live)
		test_driver_end()

/datum/unit_test/dq_p2_door/proc/run_gate()
	return

/// A turf of the 5x5 room, `dx` and `dy` from its bottom-left corner.
/datum/unit_test/dq_p2_door/proc/tile(dx, dy)
	return locate(run_loc_floor_bottom_left.x + dx, run_loc_floor_bottom_left.y + dy, run_loc_floor_bottom_left.z)

/// A powered door in the middle of the room, with `access` as its req_access when given. A test on the injected clock gets a door
/// that does not close itself (its autoclose deadline reads world.time): the live tests keep the stock timing.
/datum/unit_test/dq_p2_door/proc/make_door(type = /obj/machinery/door/airlock, list/access)
	var/obj/machinery/door/D = allocate(type, tile(2, 2))
	p2_door_set_power(D, TRUE)
	if(!live)
		p2_door_set_autoclose(D, FALSE)
	if(access)
		D.req_access = access
	return D

/// A person next to the door (east of it) wearing an ID with `access`, or no ID at all when `access` is null.
/datum/unit_test/dq_p2_door/proc/make_person(list/access, turf/where)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, where || tile(3, 2))
	// A body nobody plays is put to sleep by its life (SSD): a controller keeps it awake for as long as the test runs.
	var/mob/controller = allocate(/mob/living/simple_mob/e0_fixture, tile(0, 4))
	rel_set(H, nameof(H.teleop), controller)
	if(access)
		var/obj/item/card/id/card = allocate(/obj/item/card/id, H.loc)
		card.access = access
		card.registered_name = "P2 Tester"
		H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
		H.equip_to_slot(card, SLOT_ID_ID)
	return H

/// A silicon AI, its core off in the corner.
/datum/unit_test/dq_p2_door/proc/make_ai()
	return allocate(/mob/living/silicon/ai, tile(0, 0), null, null, null, TRUE)

/// `thing` in `H`'s active hand, whatever was there put down.
/datum/unit_test/dq_p2_door/proc/hold(mob/living/carbon/human/H, obj/item/thing)
	if(H.get_active_hand() && H.get_active_hand() != thing)
		H.drop_item()
	H.put_in_active_hand(thing)
	return thing

/// A fast tool of `type` in `H`'s active hand.
/datum/unit_test/dq_p2_door/proc/give_tool(mob/living/carbon/human/H, type)
	var/obj/item/tool = allocate(type, H.loc)
	tool.toolspeed = 0
	return hold(H, tool)

/// A lit, fuelled welder in `H`'s active hand.
/datum/unit_test/dq_p2_door/proc/give_welder(mob/living/carbon/human/H)
	var/obj/item/weldingtool/welder = give_tool(H, /obj/item/weldingtool)
	welder.reagents.add_reagent(REAGENT_ID_FUEL, welder.max_fuel)
	welder.setWelding(TRUE)
	return welder

/// Anything else in `H`'s active hand (`...`: the item's constructor arguments after its loc).
/datum/unit_test/dq_p2_door/proc/give_item(mob/living/carbon/human/H, type, ...)
	var/list/arguments = list(type, H.loc)
	if(length(args) > 2)
		arguments += args.Copy(3)
	return hold(H, allocate(arglist(arguments)))

/// A click by `H` on `target` with `held` in hand, and the time for it to play out.
/datum/unit_test/dq_p2_door/proc/click(mob/living/carbon/human/H, atom/target, obj/item/held)
	p2_door_click(H, target, held)
	settle()

/// A window button, and the time for it to play out.
/datum/unit_test/dq_p2_door/proc/press(mob/actor, datum/host, action, list/args)
	p2_door_ui(actor, host, action, args)
	settle()

/// Time for a click or a window button to play out.
/datum/unit_test/dq_p2_door/proc/settle()
	if(live)
		sleep(3 SECONDS)
	else
		p2_door_settle()

/// The sum of the sheets of `type` lying on `T`.
/datum/unit_test/dq_p2_door/proc/sheets_on(turf/T, type)
	. = 0
	for(var/obj/item/stack/S in T)
		if(istype(S, type))
			. += S.get_amount()

/// Hands everything lying on `T` to the test (sparks, blood, parts a build or a break leaves behind).
/datum/unit_test/dq_p2_door/proc/tidy(turf/T)
	own_turf_contents(T)

// =====================================================================================================================
// AIRLOCKS: opening, closing, access
// =====================================================================================================================

/datum/unit_test/dq_p2_door/airlock_opens_and_closes_for_access

/datum/unit_test/dq_p2_door/airlock_opens_and_closes_for_access/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(list(ACCESS_ENGINE))
	TEST_ASSERT(D.density, "an airlock starts closed")
	click(H, D, null)
	TEST_ASSERT(!D.density, "an ID with the access opens the door")
	TEST_ASSERT(!D.operating, "and the swing is done")
	click(H, D, null)
	TEST_ASSERT(D.density, "the same click closes it again")
	TEST_ASSERT(!D.operating, "and that swing is done")

/datum/unit_test/dq_p2_door/airlock_denies_without_access

/datum/unit_test/dq_p2_door/airlock_denies_without_access/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/stranger = make_person(null)
	var/mob/living/carbon/human/wrong = make_person(list(ACCESS_SECURITY), tile(3, 3))
	click(stranger, D, null)
	TEST_ASSERT(D.density, "a person with no ID does not open it")
	TEST_ASSERT(!D.operating, "and it never starts to move")
	click(wrong, D, null)
	TEST_ASSERT(D.density, "an ID with the wrong access does not open it")

/datum/unit_test/dq_p2_door/airlock_with_no_requirement_opens_for_anyone

/datum/unit_test/dq_p2_door/airlock_with_no_requirement_opens_for_anyone/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	click(H, D, null)
	TEST_ASSERT(!D.density, "a door with no access requirement opens for a bare hand")

/datum/unit_test/dq_p2_door/airlock_one_access_door_takes_any_listed_access

/datum/unit_test/dq_p2_door/airlock_one_access_door_takes_any_listed_access/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	D.req_one_access = list(ACCESS_ENGINE, ACCESS_SECURITY)
	var/mob/living/carbon/human/sec = make_person(list(ACCESS_SECURITY))
	var/mob/living/carbon/human/medic = make_person(list(ACCESS_MEDICAL), tile(3, 3))
	click(medic, D, null)
	TEST_ASSERT(D.density, "an ID with none of the listed accesses is refused")
	click(sec, D, null)
	TEST_ASSERT(!D.density, "an ID with one of them opens it")

/datum/unit_test/dq_p2_door/airlock_all_access_door_needs_every_access

/datum/unit_test/dq_p2_door/airlock_all_access_door_needs_every_access/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE, ACCESS_SECURITY))
	var/mob/living/carbon/human/half = make_person(list(ACCESS_ENGINE))
	var/mob/living/carbon/human/both = make_person(list(ACCESS_ENGINE, ACCESS_SECURITY), tile(3, 3))
	click(half, D, null)
	TEST_ASSERT(D.density, "one of two required accesses is not enough")
	click(both, D, null)
	TEST_ASSERT(!D.density, "both open it")

/datum/unit_test/dq_p2_door/airlock_id_card_in_hand_opens_it/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/card/id/card = give_item(H, /obj/item/card/id)
	card.access = list(ACCESS_ENGINE)
	click(H, D, card)
	TEST_ASSERT(!D.density, "swiping an ID in hand opens the door")

/datum/unit_test/dq_p2_door/airlock_bump_opens_for_access

/datum/unit_test/dq_p2_door/airlock_bump_opens_for_access/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(list(ACCESS_ENGINE))
	H.Bump(D)
	settle()
	TEST_ASSERT(!D.density, "walking into the door with access opens it")

/datum/unit_test/dq_p2_door/airlock_bump_denied_without_access

/datum/unit_test/dq_p2_door/airlock_bump_denied_without_access/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(list(ACCESS_SECURITY))
	H.Bump(D)
	settle()
	TEST_ASSERT(D.density, "walking into the door without the access leaves it shut")
	TEST_ASSERT(!D.operating, "and it does not move")

/datum/unit_test/dq_p2_door/airlock_bump_is_rate_limited
	live = TRUE

/datum/unit_test/dq_p2_door/airlock_bump_is_rate_limited/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	p2_door_set_autoclose(D, FALSE)
	var/mob/living/carbon/human/H = make_person(null)
	H.Bump(D) // refused, but it counts as a bump
	D.req_access = null
	H.Bump(D) // within the second
	sleep(2 SECONDS)
	TEST_ASSERT(D.density, "a second bump inside a second is ignored")
	H.Bump(D)
	settle()
	TEST_ASSERT(!D.density, "a bump after the cooldown opens it")

// ---------------------------------------------------------------------------------------------------------------------
// Closing itself (live: the deadline reads world.time)
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door/airlock_autocloses_after_the_normal_wait
	live = TRUE

/datum/unit_test/dq_p2_door/airlock_autocloses_after_the_normal_wait/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	click(H, D, null)
	TEST_ASSERT(!D.density, "open")
	sleep(8 SECONDS)
	TEST_ASSERT(!D.density, "it waits a good while before it closes")
	sleep(11 SECONDS)
	TEST_ASSERT(D.density, "and then closes itself")
	TEST_ASSERT(!D.operating, "with the swing done")

/datum/unit_test/dq_p2_door/airlock_fast_timing_autocloses_quickly
	live = TRUE

/datum/unit_test/dq_p2_door/airlock_fast_timing_autocloses_quickly/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_pulse(D, WIRE_SPEED, H)
	click(H, D, null)
	TEST_ASSERT(D.density, "with the timing wire pulsed the door closes itself within seconds")

/datum/unit_test/dq_p2_door/airlock_ai_speed_toggle_makes_it_close_fast
	live = TRUE

/datum/unit_test/dq_p2_door/airlock_ai_speed_toggle_makes_it_close_fast/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	var/mob/living/carbon/human/H = make_person(null)
	press(AI, D, "speed-toggle")
	click(H, D, null)
	TEST_ASSERT(D.density, "with the speed toggled by the AI the door closes itself within seconds")

/datum/unit_test/dq_p2_door/airlock_cut_timing_wire_stops_autoclose
	live = TRUE

/datum/unit_test/dq_p2_door/airlock_cut_timing_wire_stops_autoclose/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_pulse(D, WIRE_SPEED, H) // fast, so the test is short
	p2_door_wire_cut(D, WIRE_SPEED, H)
	click(H, D, null)
	sleep(4 SECONDS)
	TEST_ASSERT(!D.density, "with the timing wire cut an open door stays open")
	p2_door_wire_cut(D, WIRE_SPEED, H) // mend
	sleep(5 SECONDS)
	TEST_ASSERT(D.density, "mending the wire closes it")

// ---------------------------------------------------------------------------------------------------------------------
// Closing on someone: safeties and crushing (live)
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door/airlock_safeties_hold_door_until_clear
	live = TRUE

/datum/unit_test/dq_p2_door/airlock_safeties_hold_door_until_clear/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_pulse(D, WIRE_SPEED, H) // fast, so the test is short
	TEST_ASSERT(p2_door_safeties(D), "the safeties start on")
	p2_door_click(H, D, null)
	H.forceMove(D.loc)
	var/before = H.vitality()
	sleep(5 SECONDS)
	TEST_ASSERT(!D.density, "a door with someone in it does not close on them")
	TEST_ASSERT_EQUAL(H.vitality(), before, "and they are not hurt")
	H.forceMove(tile(3, 2))
	sleep(4 SECONDS)
	TEST_ASSERT(D.density, "it closes once they step out")

/datum/unit_test/dq_p2_door/airlock_crushes_when_safeties_are_cut
	live = TRUE

/datum/unit_test/dq_p2_door/airlock_crushes_when_safeties_are_cut/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_pulse(D, WIRE_SPEED, H) // fast, so the test is short
	p2_door_wire_pulse(D, WIRE_SAFETY, H)
	TEST_ASSERT(!p2_door_safeties(D), "pulsing the safety wire turns the safeties off")
	p2_door_click(H, D, null)
	H.forceMove(D.loc)
	var/before = H.vitality()
	var/door_before = D.get_integrity()
	sleep(5 SECONDS)
	TEST_ASSERT(D.density, "with no safeties it closes on them")
	TEST_ASSERT(H.vitality() < before, "and crushes them")
	TEST_ASSERT(D.get_integrity() < door_before, "the door takes damage from the crushing too")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/airlock_safety_wire_pulse_toggles_safeties

/datum/unit_test/dq_p2_door/airlock_safety_wire_pulse_toggles_safeties/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_pulse(D, WIRE_SAFETY, H)
	TEST_ASSERT(!p2_door_safeties(D), "a pulse turns the safeties off")
	p2_door_wire_pulse(D, WIRE_SAFETY, H)
	TEST_ASSERT(p2_door_safeties(D), "and another turns them back on")

/datum/unit_test/dq_p2_door/airlock_ai_toggles_safeties

/datum/unit_test/dq_p2_door/airlock_ai_toggles_safeties/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	press(AI, D, "safe-toggle")
	TEST_ASSERT(!p2_door_safeties(D), "the AI turns the safeties off")
	press(AI, D, "safe-toggle")
	TEST_ASSERT(p2_door_safeties(D), "and on again")

// ---------------------------------------------------------------------------------------------------------------------
// Bolts
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door/airlock_bolted_door_refuses_to_open

/datum/unit_test/dq_p2_door/airlock_bolted_door_refuses_to_open/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(list(ACCESS_ENGINE))
	p2_door_set_bolts(D, TRUE)
	TEST_ASSERT(p2_door_bolted(D), "the bolts are down")
	click(H, D, null)
	TEST_ASSERT(D.density, "a bolted door does not open for a valid ID")
	H.Bump(D)
	settle()
	TEST_ASSERT(D.density, "nor to a bump")
	p2_door_set_bolts(D, FALSE)
	click(H, D, null)
	TEST_ASSERT(!D.density, "with the bolts up it opens")

/datum/unit_test/dq_p2_door/airlock_bolted_open_door_refuses_to_close

/datum/unit_test/dq_p2_door/airlock_bolted_open_door_refuses_to_close/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	click(H, D, null)
	TEST_ASSERT(!D.density, "open")
	p2_door_set_bolts(D, TRUE)
	click(H, D, null)
	TEST_ASSERT(!D.density, "a bolted open door does not close when used")
	p2_door_set_bolts(D, FALSE)
	click(H, D, null)
	TEST_ASSERT(D.density, "with the bolts up it closes")

/datum/unit_test/dq_p2_door/airlock_bolted_open_door_does_not_autoclose
	live = TRUE

/datum/unit_test/dq_p2_door/airlock_bolted_open_door_does_not_autoclose/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_pulse(D, WIRE_SPEED, H) // fast, so the test is short
	p2_door_click(H, D, null)
	p2_door_set_bolts(D, TRUE)
	sleep(5 SECONDS)
	TEST_ASSERT(!D.density, "a bolted door does not autoclose")
	p2_door_set_bolts(D, FALSE)
	sleep(4 SECONDS)
	TEST_ASSERT(D.density, "raising the bolts lets it autoclose again")

/datum/unit_test/dq_p2_door/airlock_ai_bolt_toggle

/datum/unit_test/dq_p2_door/airlock_ai_bolt_toggle/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	press(AI, D, "bolt-toggle")
	TEST_ASSERT(p2_door_bolted(D), "the AI drops the bolts from its window")
	press(AI, D, "bolt-toggle")
	TEST_ASSERT(!p2_door_bolted(D), "and raises them again")

/datum/unit_test/dq_p2_door/airlock_bolt_wire_cut_drops_bolts_and_mending_leaves_them

/datum/unit_test/dq_p2_door/airlock_bolt_wire_cut_drops_bolts_and_mending_leaves_them/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_cut(D, WIRE_DOOR_BOLTS, H)
	TEST_ASSERT(p2_door_bolted(D), "cutting the bolt wire drops the bolts")
	p2_door_wire_cut(D, WIRE_DOOR_BOLTS, H) // mend
	TEST_ASSERT(p2_door_bolted(D), "mending the wire does not raise them")

/datum/unit_test/dq_p2_door/airlock_bolt_wire_pulse_toggles_bolts

/datum/unit_test/dq_p2_door/airlock_bolt_wire_pulse_toggles_bolts/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_pulse(D, WIRE_DOOR_BOLTS, H)
	TEST_ASSERT(p2_door_bolted(D), "a pulse drops the bolts")
	p2_door_wire_pulse(D, WIRE_DOOR_BOLTS, H)
	TEST_ASSERT(!p2_door_bolted(D), "and a second raises them")
	p2_door_set_power(D, FALSE)
	p2_door_wire_pulse(D, WIRE_DOOR_BOLTS, H)
	TEST_ASSERT(p2_door_bolted(D), "an unpowered door still drops its bolts")
	p2_door_wire_pulse(D, WIRE_DOOR_BOLTS, H)
	TEST_ASSERT(p2_door_bolted(D), "but cannot raise them without power")

/datum/unit_test/dq_p2_door/airlock_remote_button_bolts_and_unbolts

/datum/unit_test/dq_p2_door/airlock_remote_button_bolts_and_unbolts/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock/p2_test)
	var/obj/machinery/button/remote/airlock/B = allocate(/obj/machinery/button/remote/airlock/p2_test, tile(4, 2))
	p2_door_set_power(B, TRUE)
	B.specialfunctions = 4 // bolts
	var/mob/living/carbon/human/H = make_person(null, tile(4, 3))
	click(H, B, null)
	TEST_ASSERT(p2_door_bolted(D), "pressing a bolts button drops the bolts of the door with its id")
	click(H, B, null)
	TEST_ASSERT(!p2_door_bolted(D), "and pressing it again raises them")

/datum/unit_test/dq_p2_door/airlock_remote_button_opens_and_closes

/datum/unit_test/dq_p2_door/airlock_remote_button_opens_and_closes/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock/p2_test)
	var/obj/machinery/button/remote/airlock/B = allocate(/obj/machinery/button/remote/airlock/p2_test, tile(4, 2))
	p2_door_set_power(B, TRUE)
	var/mob/living/carbon/human/H = make_person(null, tile(4, 3))
	click(H, B, null)
	TEST_ASSERT(!D.density, "pressing an open button opens the door with its id")
	click(H, B, null)
	TEST_ASSERT(D.density, "and pressing it again closes it")

/datum/unit_test/dq_p2_door/airlock_radio_commands_lock_and_open

/datum/unit_test/dq_p2_door/airlock_radio_commands_lock_and_open/proc/command(obj/machinery/door/airlock/D, text)
	var/datum/signal/S = new
	S.data["tag"] = D.id_tag
	S.data["command"] = text
	D.receive_signal(S)
	p2_door_settle()

/datum/unit_test/dq_p2_door/airlock_radio_commands_lock_and_open/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock/p2_test)
	command(D, "lock")
	TEST_ASSERT(p2_door_bolted(D), "a lock command drops the bolts")
	command(D, "unlock")
	TEST_ASSERT(!p2_door_bolted(D), "an unlock command raises them")
	command(D, "open")
	TEST_ASSERT(!D.density, "an open command opens the door")
	command(D, "close")
	TEST_ASSERT(D.density, "a close command closes it")
	var/datum/signal/stranger = new
	stranger.data["tag"] = "somebody_else"
	stranger.data["command"] = "open"
	D.receive_signal(stranger)
	p2_door_settle()
	TEST_ASSERT(D.density, "a command for another tag is ignored")

// ---------------------------------------------------------------------------------------------------------------------
// The AI and the window
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door/airlock_ai_cannot_control_an_unpowered_door

/datum/unit_test/dq_p2_door/airlock_ai_cannot_control_an_unpowered_door/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	p2_door_set_power(D, FALSE)
	press(AI, D, "bolt-toggle")
	TEST_ASSERT(!p2_door_bolted(D), "an AI cannot bolt a door with no power")
	press(AI, D, "emergency-toggle")
	TEST_ASSERT(!p2_door_emergency(D), "nor engage its emergency access")

/datum/unit_test/dq_p2_door/airlock_ai_cannot_control_the_door_with_the_ai_wire_cut

/datum/unit_test/dq_p2_door/airlock_ai_cannot_control_the_door_with_the_ai_wire_cut/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_cut(D, WIRE_AI_CONTROL, H)
	press(AI, D, "bolt-toggle")
	TEST_ASSERT(!p2_door_bolted(D), "with the AI wire cut the AI cannot bolt the door")
	p2_door_wire_cut(D, WIRE_AI_CONTROL, H) // mend
	press(AI, D, "bolt-toggle")
	TEST_ASSERT(p2_door_bolted(D), "mended, it can")

/datum/unit_test/dq_p2_door/airlock_ai_opens_and_closes_the_door

/datum/unit_test/dq_p2_door/airlock_ai_opens_and_closes_the_door/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	press(AI, D, "open-close")
	TEST_ASSERT(!D.density, "the AI opens it from its window")
	press(AI, D, "open-close")
	TEST_ASSERT(D.density, "and closes it")
	p2_door_set_bolts(D, TRUE)
	press(AI, D, "open-close")
	TEST_ASSERT(D.density, "a bolted door ignores it")
	p2_door_set_bolts(D, FALSE)
	p2_door_set_welded(D, TRUE)
	press(AI, D, "open-close")
	TEST_ASSERT(D.density, "and so does a welded one")

/datum/unit_test/dq_p2_door/airlock_ai_toggles_emergency_access

/datum/unit_test/dq_p2_door/airlock_ai_toggles_emergency_access/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/silicon/ai/AI = make_ai()
	var/mob/living/carbon/human/stranger = make_person(null)
	click(stranger, D, null)
	TEST_ASSERT(D.density, "a stranger cannot open an access door")
	press(AI, D, "emergency-toggle")
	TEST_ASSERT(p2_door_emergency(D), "the AI engages emergency access")
	click(stranger, D, null)
	TEST_ASSERT(!D.density, "now anyone can open it")
	press(AI, D, "emergency-toggle")
	TEST_ASSERT(!p2_door_emergency(D), "and it can be disengaged")

/datum/unit_test/dq_p2_door/airlock_ai_idscan_toggle_blocks_valid_ids

/datum/unit_test/dq_p2_door/airlock_ai_idscan_toggle_blocks_valid_ids/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/silicon/ai/AI = make_ai()
	var/mob/living/carbon/human/H = make_person(list(ACCESS_ENGINE))
	press(AI, D, "idscan-toggle")
	click(H, D, null)
	TEST_ASSERT(D.density, "with the ID scanner off, even a valid ID does not open the door")
	press(AI, D, "idscan-toggle")
	click(H, D, null)
	TEST_ASSERT(!D.density, "with it back on, it does")

/datum/unit_test/dq_p2_door/airlock_ai_toggles_the_bolt_lights

/datum/unit_test/dq_p2_door/airlock_ai_toggles_the_bolt_lights/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	var/before = D.lights
	press(AI, D, "light-toggle")
	TEST_ASSERT_NOTEQUAL(D.lights, before, "the AI switches the bolt lights")
	press(AI, D, "light-toggle")
	TEST_ASSERT_EQUAL(D.lights, before, "and back")

/datum/unit_test/dq_p2_door/airlock_cut_idscan_wire_blocks_valid_ids

/datum/unit_test/dq_p2_door/airlock_cut_idscan_wire_blocks_valid_ids/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(list(ACCESS_ENGINE))
	p2_door_wire_cut(D, WIRE_IDSCAN, H)
	click(H, D, null)
	TEST_ASSERT(D.density, "with the ID scan wire cut a valid ID is not read")
	p2_door_wire_cut(D, WIRE_IDSCAN, H) // mend
	click(H, D, null)
	TEST_ASSERT(!D.density, "mended, the door reads it")

/datum/unit_test/dq_p2_door/airlock_open_door_wire_pulse_opens_a_door_with_no_access

/datum/unit_test/dq_p2_door/airlock_open_door_wire_pulse_opens_a_door_with_no_access/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_pulse(D, WIRE_OPEN_DOOR, H)
	settle()
	TEST_ASSERT(!D.density, "a pulse on the open-door wire opens a door that asks for no access")
	p2_door_wire_pulse(D, WIRE_OPEN_DOOR, H)
	settle()
	TEST_ASSERT(D.density, "and a second one closes it")

/datum/unit_test/dq_p2_door/airlock_open_door_wire_pulse_refused_by_an_access_door

/datum/unit_test/dq_p2_door/airlock_open_door_wire_pulse_refused_by_an_access_door/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_pulse(D, WIRE_OPEN_DOOR, H)
	settle()
	TEST_ASSERT(D.density, "a pulse does not open a door that wants an ID")

// ---------------------------------------------------------------------------------------------------------------------
// The maintenance panel
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door/airlock_screwdriver_opens_and_closes_the_panel

/datum/unit_test/dq_p2_door/airlock_screwdriver_opens_and_closes_the_panel/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/driver = give_tool(H, /obj/item/tool/screwdriver)
	TEST_ASSERT(!p2_door_panel_open(D), "the panel starts closed")
	click(H, D, driver)
	TEST_ASSERT(p2_door_panel_open(D), "a screwdriver opens it")
	click(H, D, driver)
	TEST_ASSERT(!p2_door_panel_open(D), "and closes it")

/datum/unit_test/dq_p2_door/airlock_open_panel_door_does_not_open_on_a_bump

/datum/unit_test/dq_p2_door/airlock_open_panel_door_does_not_open_on_a_bump/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/driver = give_tool(H, /obj/item/tool/screwdriver)
	click(H, D, driver)
	TEST_ASSERT(p2_door_panel_open(D), "panel open")
	H.Bump(D)
	settle()
	TEST_ASSERT(D.density, "walking into a door with its panel open does not open it")

// ---------------------------------------------------------------------------------------------------------------------
// Welding
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door/airlock_welder_welds_shut_and_unwelds

/datum/unit_test/dq_p2_door/airlock_welder_welds_shut_and_unwelds/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/weldingtool/welder = give_welder(H)
	click(H, D, welder)
	TEST_ASSERT(p2_door_welded(D), "a lit welder welds a closed door shut")
	click(H, D, welder)
	TEST_ASSERT(!p2_door_welded(D), "and frees it again")

/datum/unit_test/dq_p2_door/airlock_welded_door_refuses_to_open

/datum/unit_test/dq_p2_door/airlock_welded_door_refuses_to_open/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_set_welded(D, TRUE)
	click(H, D, null)
	TEST_ASSERT(D.density, "a welded door does not open by hand")
	H.Bump(D)
	settle()
	TEST_ASSERT(D.density, "nor by a bump")
	p2_door_set_welded(D, FALSE)
	click(H, D, null)
	TEST_ASSERT(!D.density, "unwelded, it opens")

/datum/unit_test/dq_p2_door/airlock_welded_open_door_does_not_close

/datum/unit_test/dq_p2_door/airlock_welded_open_door_does_not_close/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	click(H, D, null)
	TEST_ASSERT(!D.density, "open")
	p2_door_set_welded(D, TRUE)
	click(H, D, null)
	TEST_ASSERT(!D.density, "a welded open door does not close by hand")

/datum/unit_test/dq_p2_door/airlock_welded_open_door_does_not_autoclose
	live = TRUE

/datum/unit_test/dq_p2_door/airlock_welded_open_door_does_not_autoclose/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_pulse(D, WIRE_SPEED, H) // fast, so the test is short
	p2_door_click(H, D, null)
	p2_door_set_welded(D, TRUE)
	sleep(5 SECONDS)
	TEST_ASSERT(!D.density, "a welded open door does not close itself")

/datum/unit_test/dq_p2_door/airlock_welder_will_not_weld_an_open_door

/datum/unit_test/dq_p2_door/airlock_welder_will_not_weld_an_open_door/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	click(H, D, null) // bare hand: opens
	TEST_ASSERT(!D.density, "open")
	var/obj/item/weldingtool/welder = give_welder(H)
	click(H, D, welder)
	TEST_ASSERT(!p2_door_welded(D), "an open door cannot be welded")

/datum/unit_test/dq_p2_door/airlock_examine_changes_with_welding_and_emergency_access

/datum/unit_test/dq_p2_door/airlock_examine_changes_with_welding_and_emergency_access/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	var/mob/living/silicon/ai/AI = make_ai()
	var/plain = p2_door_examine(D, H)
	p2_door_set_welded(D, TRUE)
	var/welded = p2_door_examine(D, H)
	TEST_ASSERT_NOTEQUAL(welded, plain, "a welded door reads differently when examined")
	p2_door_set_welded(D, FALSE)
	TEST_ASSERT_EQUAL(p2_door_examine(D, H), plain, "and reads the same again once freed")
	press(AI, D, "emergency-toggle")
	TEST_ASSERT_NOTEQUAL(p2_door_examine(D, H), plain, "an engaged emergency access shows when examined")

// ---------------------------------------------------------------------------------------------------------------------
// Prying
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door/airlock_powered_door_resists_a_crowbar

/datum/unit_test/dq_p2_door/airlock_powered_door_resists_a_crowbar/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/crowbar = give_tool(H, /obj/item/tool/crowbar)
	click(H, D, crowbar)
	TEST_ASSERT(D.density, "a powered airlock cannot be pried open")

/datum/unit_test/dq_p2_door/airlock_strong_animal_breaks_into_a_bolted_dead_one

/datum/unit_test/dq_p2_door/airlock_strong_animal_breaks_into_a_bolted_dead_one/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	p2_door_set_power(D, FALSE)
	p2_door_set_bolts(D, TRUE)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, tile(3, 2))
	generic_hit(D, M, 1)
	test_time(11 SECONDS)
	TEST_ASSERT(D.density, "a weak animal strains for nothing")
	generic_hit(D, M, 50)
	test_time(11 SECONDS)
	TEST_ASSERT(!D.density, "a strong one breaks in")
	TEST_ASSERT(!p2_door_bolted(D), "through the bolts")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/airlock_strong_animal_breaks_into_a_bolted_dead_one

/datum/unit_test/dq_p2_door/airlock_strong_animal_breaks_into_a_bolted_dead_one/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	p2_door_set_power(D, FALSE)
	p2_door_set_bolts(D, TRUE)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, tile(3, 2))
	generic_hit(D, M, 1)
	test_time(11 SECONDS)
	TEST_ASSERT(D.density, "a weak animal strains for nothing")
	generic_hit(D, M, 50)
	test_time(11 SECONDS)
	TEST_ASSERT(!D.density, "a strong one breaks in")
	TEST_ASSERT(!p2_door_bolted(D), "through the bolts")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/emag_target_subverts_a_door_without_a_card

/datum/unit_test/dq_p2_door/emag_target_subverts_a_door_without_a_card/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	TEST_ASSERT(emag_target(D, 1) != EMAG_DECLINED, "an event's emag works on a door")
	settle()
	TEST_ASSERT(!D.density, "and the door gives way")
	TEST_ASSERT(p2_door_emagged(D), "for good")
	TEST_ASSERT_EQUAL(emag_target(D, 1), EMAG_DECLINED, "a second emag is declined")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/airlock_unpowered_door_pries_open_and_shut

/datum/unit_test/dq_p2_door/airlock_unpowered_door_pries_open_and_shut/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/crowbar = give_tool(H, /obj/item/tool/crowbar)
	p2_door_set_power(D, FALSE)
	click(H, D, crowbar)
	TEST_ASSERT(!D.density, "a crowbar forces an unpowered door open")
	click(H, D, crowbar)
	TEST_ASSERT(D.density, "the crowbar forces it shut again")

/datum/unit_test/dq_p2_door/airlock_unpowered_open_door_does_not_autoclose
	live = TRUE

/datum/unit_test/dq_p2_door/airlock_unpowered_open_door_does_not_autoclose/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_pulse(D, WIRE_SPEED, H) // fast, so the test is short
	p2_door_click(H, D, null)
	p2_door_set_power(D, FALSE)
	sleep(5 SECONDS)
	TEST_ASSERT(!D.density, "a door with no power does not close itself")

/datum/unit_test/dq_p2_door/airlock_bolts_and_welds_refuse_a_crowbar

/datum/unit_test/dq_p2_door/airlock_bolts_and_welds_refuse_a_crowbar/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/crowbar = give_tool(H, /obj/item/tool/crowbar)
	p2_door_set_power(D, FALSE)
	p2_door_set_bolts(D, TRUE)
	click(H, D, crowbar)
	TEST_ASSERT(D.density, "a bolted door cannot be pried")
	p2_door_set_bolts(D, FALSE)
	p2_door_set_welded(D, TRUE)
	click(H, D, crowbar)
	TEST_ASSERT(D.density, "a welded door cannot be pried")
	p2_door_set_welded(D, FALSE)
	click(H, D, crowbar)
	TEST_ASSERT(!D.density, "free of both it can")

// ---------------------------------------------------------------------------------------------------------------------
// Electrification
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door/airlock_wire_pulse_electrifies_for_a_while

/datum/unit_test/dq_p2_door/airlock_wire_pulse_electrifies_for_a_while/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	TEST_ASSERT(!p2_door_electrified(D), "a door starts safe")
	p2_door_wire_pulse(D, WIRE_ELECTRIFY, H)
	TEST_ASSERT(p2_door_electrified(D), "a pulse electrifies it")
	test_time(20 SECONDS)
	TEST_ASSERT(p2_door_electrified(D), "for longer than twenty seconds")
	test_time(15 SECONDS)
	TEST_ASSERT(!p2_door_electrified(D), "but it wears off after thirty")

/datum/unit_test/dq_p2_door/airlock_cut_electrify_wire_is_permanent_until_mended

/datum/unit_test/dq_p2_door/airlock_cut_electrify_wire_is_permanent_until_mended/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_cut(D, WIRE_ELECTRIFY, H)
	TEST_ASSERT(p2_door_electrified(D), "cutting the wire electrifies the door")
	test_time(2 MINUTES)
	TEST_ASSERT(p2_door_electrified(D), "and it stays so")
	p2_door_wire_cut(D, WIRE_ELECTRIFY, H) // mend
	TEST_ASSERT(!p2_door_electrified(D), "mending it ends the current")

/datum/unit_test/dq_p2_door/airlock_ai_electrifies_and_restores

/datum/unit_test/dq_p2_door/airlock_ai_electrifies_and_restores/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	p2_door_ui(AI, D, "shock-temp")
	TEST_ASSERT(p2_door_electrified(D), "the AI electrifies the door")
	test_time(35 SECONDS)
	TEST_ASSERT(!p2_door_electrified(D), "for thirty seconds")
	p2_door_ui(AI, D, "shock-perm")
	test_time(2 MINUTES)
	TEST_ASSERT(p2_door_electrified(D), "or for good")
	p2_door_ui(AI, D, "shock-restore")
	TEST_ASSERT(!p2_door_electrified(D), "until it restores the door")

/datum/unit_test/dq_p2_door/airlock_remote_button_electrifies_and_restores

/datum/unit_test/dq_p2_door/airlock_remote_button_electrifies_and_restores/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock/p2_test)
	var/obj/machinery/button/remote/airlock/B = allocate(/obj/machinery/button/remote/airlock/p2_test, tile(4, 2))
	p2_door_set_power(B, TRUE)
	B.specialfunctions = 8 // shock
	var/mob/living/carbon/human/H = make_person(null, tile(4, 3))
	click(H, B, null)
	TEST_ASSERT(p2_door_electrified(D), "a shock button electrifies the door with its id for good")
	click(H, B, null)
	TEST_ASSERT(!p2_door_electrified(D), "and pressing it again ends it")

// ---------------------------------------------------------------------------------------------------------------------
// Power
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door/airlock_main_power_loss_is_carried_by_backup

/datum/unit_test/dq_p2_door/airlock_main_power_loss_is_carried_by_backup/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	TEST_ASSERT(p2_door_powered(D), "powered")
	p2_door_wire_pulse(D, WIRE_MAIN_POWER1, H)
	TEST_ASSERT(!p2_door_powered(D), "a pulse on the main power trips the breaker")
	test_time(1 SECONDS)
	p2_door_click(H, D, null)
	test_time(1 SECONDS)
	TEST_ASSERT(D.density, "a door with no power does not open")
	test_time(11 SECONDS)
	TEST_ASSERT(p2_door_powered(D), "ten seconds on, the backup power carries it")
	click(H, D, null)
	TEST_ASSERT(!D.density, "and it works again")
	test_time(70 SECONDS)
	TEST_ASSERT(p2_door_powered(D), "when main power returns it is still powered")

/datum/unit_test/dq_p2_door/airlock_ai_can_drop_main_and_backup_power

/datum/unit_test/dq_p2_door/airlock_ai_can_drop_main_and_backup_power/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	p2_door_ui(AI, D, "disrupt-main")
	TEST_ASSERT(!p2_door_powered(D), "main power dropped")
	test_time(11 SECONDS)
	TEST_ASSERT(p2_door_powered(D), "the backup takes over")
	p2_door_ui(AI, D, "disrupt-backup")
	TEST_ASSERT(!p2_door_powered(D), "dropping the backup too leaves nothing")
	test_time(70 SECONDS)
	TEST_ASSERT(p2_door_powered(D), "both come back in a minute")

/datum/unit_test/dq_p2_door/airlock_mending_a_cut_power_wire_restores_power

/datum/unit_test/dq_p2_door/airlock_mending_a_cut_power_wire_restores_power/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_cut(D, WIRE_MAIN_POWER1, H)
	TEST_ASSERT(!p2_door_powered(D), "cutting main power darkens the door")
	test_time(11 SECONDS)
	TEST_ASSERT(p2_door_powered(D), "the backup carries it ten seconds later")
	p2_door_wire_cut(D, WIRE_MAIN_POWER1, H) // mend
	TEST_ASSERT(p2_door_powered(D), "mending the wire leaves it powered")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/airlock_without_area_power_does_not_open

/datum/unit_test/dq_p2_door/airlock_without_area_power_does_not_open/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_set_power(D, FALSE)
	click(H, D, null)
	TEST_ASSERT(D.density, "a door off area power does not open by hand")
	H.Bump(D)
	settle()
	TEST_ASSERT(D.density, "nor by a bump")
	p2_door_set_power(D, TRUE)
	click(H, D, null)
	TEST_ASSERT(!D.density, "with power restored it does")

// ---------------------------------------------------------------------------------------------------------------------
// Emag
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door/airlock_emag_opens_it

/datum/unit_test/dq_p2_door/airlock_emag_opens_it/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/card/emag/emag = give_item(H, /obj/item/card/emag)
	var/uses = emag.uses
	click(H, D, emag)
	TEST_ASSERT(!D.density, "a cryptographic sequencer opens the door")
	TEST_ASSERT(p2_door_emagged(D), "and marks it emagged")
	TEST_ASSERT_EQUAL(emag.uses, uses - 1, "spending one charge")

/datum/unit_test/dq_p2_door/airlock_emag_declines_an_open_door

/datum/unit_test/dq_p2_door/airlock_emag_declines_an_open_door/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/card/emag/emag = give_item(H, /obj/item/card/emag)
	click(H, D, emag)
	var/uses = emag.uses
	click(H, D, emag)
	TEST_ASSERT_EQUAL(emag.uses, uses, "a second swipe on the already open door spends nothing")

/datum/unit_test/dq_p2_door/airlock_emag_declines_an_unpowered_door

/datum/unit_test/dq_p2_door/airlock_emag_declines_an_unpowered_door/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/card/emag/emag = give_item(H, /obj/item/card/emag)
	var/uses = emag.uses
	p2_door_set_power(D, FALSE)
	click(H, D, emag)
	TEST_ASSERT(D.density, "a dead door cannot be emagged open")
	TEST_ASSERT(!p2_door_emagged(D), "and is not marked emagged")
	TEST_ASSERT_EQUAL(emag.uses, uses, "no charge is spent")

// ---------------------------------------------------------------------------------------------------------------------
// Damage, breaking, repair and reinforcement
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door/airlock_strike_with_a_heavy_item_damages_it/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/bar = give_item(H, /obj/item/pen)
	bar.force = 30
	H.set_combat_mode(TRUE)
	var/before = D.get_integrity()
	click(H, D, bar)
	TEST_ASSERT(D.get_integrity() < before, "a hard hit in combat mode damages the door")
	TEST_ASSERT(D.density, "and it stays shut")

/datum/unit_test/dq_p2_door/airlock_weak_strike_does_nothing/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/bar = give_item(H, /obj/item/pen)
	bar.force = 2
	H.set_combat_mode(TRUE)
	var/before = D.get_integrity()
	click(H, D, bar)
	TEST_ASSERT_EQUAL(D.get_integrity(), before, "a hit below the door's minimum force leaves no mark")

/datum/unit_test/dq_p2_door/airlock_breaks_and_pops_its_panel

/datum/unit_test/dq_p2_door/airlock_breaks_and_pops_its_panel/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	var/plain = p2_door_examine(D, H)
	D.take_damage(D.max_integrity * 0.5, BRUTE, MELEE)
	TEST_ASSERT(!D.has_stat(BROKEN), "half damage does not break it")
	D.take_damage(D.max_integrity * 0.3, BRUTE, MELEE)
	TEST_ASSERT(D.has_stat(BROKEN), "past three quarters damage it breaks")
	TEST_ASSERT(p2_door_panel_open(D), "its panel bursts open")
	TEST_ASSERT_NOTEQUAL(p2_door_examine(D, H), plain, "examining it reads differently")
	click(H, D, null)
	TEST_ASSERT(D.density, "a broken door does not open by hand")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/airlock_welder_repairs_damage/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/weldingtool/welder = give_welder(H)
	D.take_damage(D.max_integrity * 0.1, BRUTE, MELEE)
	TEST_ASSERT(D.get_integrity() < D.max_integrity, "damaged")
	p2_door_click(H, D, welder)
	test_time(60 SECONDS)
	TEST_ASSERT_EQUAL(D.get_integrity(), D.max_integrity, "a welder repairs a damaged door instead of welding it shut")
	TEST_ASSERT(!p2_door_welded(D), "and does not weld it")

/datum/unit_test/dq_p2_door/airlock_welder_repairs_a_broken_door

/datum/unit_test/dq_p2_door/airlock_welder_repairs_a_broken_door/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/weldingtool/welder = give_welder(H)
	D.take_damage(D.max_integrity * 0.9, BRUTE, MELEE)
	TEST_ASSERT(D.has_stat(BROKEN), "broken")
	p2_door_click(H, D, welder)
	test_time(120 SECONDS)
	TEST_ASSERT_EQUAL(D.get_integrity(), D.max_integrity, "welding restores its integrity")
	TEST_ASSERT(!D.has_stat(BROKEN), "and mends the break")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/airlock_welding_fitted_plasteel_reinforces_the_door

/datum/unit_test/dq_p2_door/airlock_welding_fitted_plasteel_reinforces_the_door/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	D.reinforcing = 2 // two sheets fitted
	TEST_ASSERT(!D.heat_proof, "not reinforced yet")
	click(H, D, give_welder(H))
	TEST_ASSERT(D.heat_proof, "welding the fitted plasteel in reinforces the door")
	TEST_ASSERT_EQUAL(D.reinforcing, 0, "and nothing is left waiting to be welded")

/datum/unit_test/dq_p2_door/airlock_fitted_plasteel_can_be_pried_back_off

/datum/unit_test/dq_p2_door/airlock_fitted_plasteel_can_be_pried_back_off/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	D.reinforcing = 2 // two sheets fitted
	click(H, D, give_tool(H, /obj/item/tool/crowbar))
	TEST_ASSERT_EQUAL(D.reinforcing, 0, "a crowbar takes the unwelded plasteel back off")
	TEST_ASSERT(!D.heat_proof, "the door is not reinforced")
	TEST_ASSERT_EQUAL(sheets_on(tile(2, 2), /obj/item/stack/material/plasteel), 2, "and the sheets are on the floor")
	tidy(tile(2, 2))

// ---------------------------------------------------------------------------------------------------------------------
// EMP
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door/airlock_emp_can_pop_it_open

/datum/unit_test/dq_p2_door/airlock_emp_can_pop_it_open/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	D.emp_protection_flags |= EMP_PROTECT_WIRES | EMP_PROTECT_CONTENTS
	test_rng(1234)
	var/opened = FALSE
	for(var/i in 1 to 300)
		D.emp_act(1)
		test_time(1 SECONDS)
		if(!D.density)
			opened = TRUE
			break
	TEST_ASSERT(opened, "a strong EMP pops an airlock open sometimes")

/datum/unit_test/dq_p2_door/airlock_emp_can_electrify_it

/datum/unit_test/dq_p2_door/airlock_emp_can_electrify_it/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	D.emp_protection_flags |= EMP_PROTECT_WIRES | EMP_PROTECT_CONTENTS
	test_rng(4321)
	var/electrified = FALSE
	for(var/i in 1 to 300)
		D.emp_act(1)
		if(p2_door_electrified(D))
			electrified = TRUE
			break
	TEST_ASSERT(electrified, "an EMP electrifies an airlock sometimes")
	test_time(40 SECONDS)
	TEST_ASSERT(!p2_door_electrified(D), "and it wears off")

// =====================================================================================================================
// AIRLOCK ELECTRONICS
// =====================================================================================================================

/datum/unit_test/dq_p2_door/electronics_unlock_for_an_engineer_and_set_access

/datum/unit_test/dq_p2_door/electronics_unlock_for_an_engineer_and_set_access/run_gate()
	var/obj/item/airlock_electronics/E = allocate(/obj/item/airlock_electronics, tile(2, 2))
	var/mob/living/carbon/human/engineer = make_person(list(ACCESS_ENGINE))
	TEST_ASSERT(E.locked, "electronics start locked")
	press(engineer, E, "access", list("access" = ACCESS_SECURITY))
	TEST_ASSERT(isnull(E.conf_access), "a locked device takes no access changes")
	press(engineer, E, "login")
	TEST_ASSERT(!E.locked, "an engineer's ID unlocks it")
	TEST_ASSERT_EQUAL(E.last_configurator, "P2 Tester", "and it remembers who")
	press(engineer, E, "access", list("access" = ACCESS_SECURITY))
	TEST_ASSERT(ACCESS_SECURITY in E.conf_access, "an access is switched on")
	press(engineer, E, "access", list("access" = ACCESS_MEDICAL))
	TEST_ASSERT((ACCESS_SECURITY in E.conf_access) && (ACCESS_MEDICAL in E.conf_access), "and another beside it")
	press(engineer, E, "access", list("access" = ACCESS_SECURITY))
	TEST_ASSERT(!(ACCESS_SECURITY in E.conf_access), "switching it again turns it off")
	TEST_ASSERT(ACCESS_MEDICAL in E.conf_access, "leaving the other")
	press(engineer, E, "one_access")
	TEST_ASSERT(E.one_access, "the one-access switch flips")
	press(engineer, E, "logout")
	TEST_ASSERT(E.locked, "logging out locks it again")

/datum/unit_test/dq_p2_door/electronics_stay_locked_for_a_stranger

/datum/unit_test/dq_p2_door/electronics_stay_locked_for_a_stranger/run_gate()
	var/obj/item/airlock_electronics/E = allocate(/obj/item/airlock_electronics, tile(2, 2))
	var/mob/living/carbon/human/medic = make_person(list(ACCESS_MEDICAL))
	var/mob/living/carbon/human/bare = make_person(null, tile(3, 3))
	press(medic, E, "login")
	TEST_ASSERT(E.locked, "an ID without engineering access does not unlock it")
	press(bare, E, "login")
	TEST_ASSERT(E.locked, "nor does a bare hand")

/datum/unit_test/dq_p2_door/electronics_non_engineer_may_set_only_their_own_access

/datum/unit_test/dq_p2_door/electronics_non_engineer_may_set_only_their_own_access/run_gate()
	var/obj/item/airlock_electronics/E = allocate(/obj/item/airlock_electronics, tile(2, 2))
	E.req_one_access = list(ACCESS_MEDICAL) // the unlocking ID for this device
	var/mob/living/carbon/human/medic = make_person(list(ACCESS_MEDICAL))
	press(medic, E, "login")
	TEST_ASSERT(!E.locked, "the right ID unlocks it")
	press(medic, E, "access", list("access" = ACCESS_SECURITY))
	TEST_ASSERT(isnull(E.conf_access), "an access the person does not hold cannot be set")
	press(medic, E, "access", list("access" = ACCESS_MEDICAL))
	TEST_ASSERT(ACCESS_MEDICAL in E.conf_access, "one they hold can")

/datum/unit_test/dq_p2_door/electronics_emag_removes_the_lock

/datum/unit_test/dq_p2_door/electronics_emag_removes_the_lock/run_gate()
	var/obj/item/airlock_electronics/E = allocate(/obj/item/airlock_electronics, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/card/emag/emag = give_item(H, /obj/item/card/emag)
	var/uses = emag.uses
	click(H, E, emag)
	TEST_ASSERT(E.emagged, "a cryptographic sequencer strips the electronics' restrictions")
	TEST_ASSERT_EQUAL(emag.uses, uses - 1, "spending a charge")
	press(H, E, "login")
	TEST_ASSERT(!E.locked, "anyone can now log in")
	click(H, E, emag)
	TEST_ASSERT_EQUAL(emag.uses, uses - 1, "a second swipe spends nothing")

/datum/unit_test/dq_p2_door/electronics_secure_ones_resist_the_emag

/datum/unit_test/dq_p2_door/electronics_secure_ones_resist_the_emag/run_gate()
	var/obj/item/airlock_electronics/secure/E = allocate(/obj/item/airlock_electronics/secure, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/card/emag/emag = give_item(H, /obj/item/card/emag)
	var/uses = emag.uses
	click(H, E, emag)
	TEST_ASSERT(!E.emagged, "secure electronics cannot be emagged")
	TEST_ASSERT_EQUAL(emag.uses, uses, "and no charge is spent")

// =====================================================================================================================
// AIRLOCK ASSEMBLIES
// =====================================================================================================================

/// Walks an airlock assembly through its frame, wiring and electronics (as `H` with the access `access` set on the board).
/datum/unit_test/dq_p2_door/proc/frame_up(obj/structure/door_assembly/A, mob/living/carbon/human/H, list/access)
	var/obj/item/airlock_electronics/board = allocate(/obj/item/airlock_electronics, H.loc)
	board.conf_access = access
	click(H, A, give_tool(H, /obj/item/tool/wrench))
	if(!A.anchored)
		return null
	click(H, A, give_item(H, /obj/item/stack/cable_coil, 5))
	if(p2_door_assembly_state(A) != 1)
		return null
	click(H, A, hold(H, board))
	return board

/datum/unit_test/dq_p2_door/door_assembly_builds_an_airlock

/datum/unit_test/dq_p2_door/door_assembly_builds_an_airlock/run_gate()
	var/obj/structure/door_assembly/A = allocate(/obj/structure/door_assembly, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/airlock_electronics/board = allocate(/obj/item/airlock_electronics, H.loc)
	board.conf_access = list(ACCESS_ENGINE)
	TEST_ASSERT(!A.anchored, "a new assembly is loose")
	TEST_ASSERT_EQUAL(p2_door_assembly_state(A), 0, "and bare")
	click(H, A, give_tool(H, /obj/item/tool/wrench))
	TEST_ASSERT(A.anchored, "a wrench bolts it to the floor")
	var/obj/item/stack/cable_coil/cable = give_item(H, /obj/item/stack/cable_coil, 5)
	click(H, A, cable)
	TEST_ASSERT_EQUAL(p2_door_assembly_state(A), 1, "cable wires it")
	TEST_ASSERT_EQUAL(cable.get_amount(), 4, "using one length")
	click(H, A, hold(H, board))
	TEST_ASSERT_EQUAL(p2_door_assembly_state(A), 2, "electronics go in")
	TEST_ASSERT_EQUAL(A.electronics, board, "and the assembly keeps them")
	click(H, A, give_tool(H, /obj/item/tool/screwdriver))
	TEST_ASSERT(QDELETED(A), "a screwdriver finishes the airlock")
	var/obj/machinery/door/airlock/D = locate(/obj/machinery/door/airlock) in tile(2, 2)
	TEST_ASSERT_NOTNULL(D, "an airlock stands where the assembly was")
	own(D)
	TEST_ASSERT(D.density, "closed")
	TEST_ASSERT(D.req_access ~= list(ACCESS_ENGINE), "with the access from its electronics")
	TEST_ASSERT_EQUAL(D.electronics, board, "which sit inside it")
	p2_door_set_power(D, TRUE)
	p2_door_set_autoclose(D, FALSE)
	var/mob/living/carbon/human/engineer = make_person(list(ACCESS_ENGINE), tile(3, 3))
	var/mob/living/carbon/human/stranger = make_person(null, tile(3, 1))
	click(stranger, D, null)
	TEST_ASSERT(D.density, "a stranger cannot open it")
	click(engineer, D, null)
	TEST_ASSERT(!D.density, "an engineer can")

/datum/unit_test/dq_p2_door/door_assembly_one_access_electronics_make_a_one_access_door

/datum/unit_test/dq_p2_door/door_assembly_one_access_electronics_make_a_one_access_door/run_gate()
	var/obj/structure/door_assembly/A = allocate(/obj/structure/door_assembly, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/airlock_electronics/board = frame_up(A, H, list(ACCESS_ENGINE, ACCESS_SECURITY))
	TEST_ASSERT_NOTNULL(board, "the frame went up")
	board.one_access = TRUE
	click(H, A, give_tool(H, /obj/item/tool/screwdriver))
	var/obj/machinery/door/airlock/D = locate(/obj/machinery/door/airlock) in tile(2, 2)
	TEST_ASSERT_NOTNULL(D, "an airlock stands where the assembly was")
	own(D)
	TEST_ASSERT(D.req_one_access ~= list(ACCESS_ENGINE, ACCESS_SECURITY), "its access is any-of")
	TEST_ASSERT(!LAZYLEN(D.req_access), "not all-of")

/datum/unit_test/dq_p2_door/door_assembly_steps_can_be_undone

/datum/unit_test/dq_p2_door/door_assembly_steps_can_be_undone/run_gate()
	var/obj/structure/door_assembly/A = allocate(/obj/structure/door_assembly, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/airlock_electronics/board = frame_up(A, H, list(ACCESS_ENGINE))
	TEST_ASSERT_NOTNULL(board, "the frame went up")
	TEST_ASSERT_EQUAL(p2_door_assembly_state(A), 2, "electronics in")
	click(H, A, give_tool(H, /obj/item/tool/crowbar))
	TEST_ASSERT_EQUAL(p2_door_assembly_state(A), 1, "a crowbar takes the electronics out")
	TEST_ASSERT_NULL(A.electronics, "the assembly no longer holds them")
	TEST_ASSERT_EQUAL(board.loc, tile(2, 2), "they lie on the floor")
	click(H, A, give_tool(H, /obj/item/tool/wirecutters))
	TEST_ASSERT_EQUAL(p2_door_assembly_state(A), 0, "wirecutters strip the wiring")
	TEST_ASSERT(A.anchored, "the frame is still bolted down")
	click(H, A, give_tool(H, /obj/item/tool/wrench))
	TEST_ASSERT(!A.anchored, "a wrench frees it again")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/door_assembly_wiring_needs_a_bolted_frame

/datum/unit_test/dq_p2_door/door_assembly_wiring_needs_a_bolted_frame/run_gate()
	var/obj/structure/door_assembly/A = allocate(/obj/structure/door_assembly, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/stack/cable_coil/cable = give_item(H, /obj/item/stack/cable_coil, 5)
	click(H, A, cable)
	TEST_ASSERT_EQUAL(p2_door_assembly_state(A), 0, "a loose frame cannot be wired")
	TEST_ASSERT_EQUAL(cable.get_amount(), 5, "and no cable is used")

/datum/unit_test/dq_p2_door/door_assembly_electronics_need_wiring_first

/datum/unit_test/dq_p2_door/door_assembly_electronics_need_wiring_first/run_gate()
	var/obj/structure/door_assembly/A = allocate(/obj/structure/door_assembly, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/airlock_electronics/board = give_item(H, /obj/item/airlock_electronics)
	click(H, A, board)
	TEST_ASSERT_NULL(A.electronics, "a bare frame takes no electronics")

/datum/unit_test/dq_p2_door/door_assembly_takes_glass_and_gives_it_back

/datum/unit_test/dq_p2_door/door_assembly_takes_glass_and_gives_it_back/run_gate()
	var/obj/structure/door_assembly/A = allocate(/obj/structure/door_assembly, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/stack/material/glass/reinforced/glass = give_item(H, /obj/item/stack/material/glass/reinforced, 3)
	click(H, A, glass)
	TEST_ASSERT_EQUAL(A.glass, 1, "reinforced glass windows the assembly")
	TEST_ASSERT_EQUAL(glass.get_amount(), 2, "using one sheet")
	click(H, A, give_welder(H))
	TEST_ASSERT_EQUAL(A.glass, 0, "a welder cuts the window out")
	TEST_ASSERT(sheets_on(tile(2, 2), /obj/item/stack/material/glass/reinforced) >= 1, "and the glass is left on the floor")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/door_assembly_takes_mineral_plating_and_gives_it_back

/datum/unit_test/dq_p2_door/door_assembly_takes_mineral_plating_and_gives_it_back/run_gate()
	var/obj/structure/door_assembly/A = allocate(/obj/structure/door_assembly, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/stack/material/gold/gold = give_item(H, /obj/item/stack/material/gold, 4)
	click(H, A, gold)
	TEST_ASSERT(istext(A.glass), "gold plates the assembly")
	TEST_ASSERT_EQUAL(gold.get_amount(), 2, "using two sheets")
	click(H, A, give_welder(H))
	TEST_ASSERT_EQUAL(A.glass, 0, "a welder strips the plating")
	TEST_ASSERT_EQUAL(sheets_on(tile(2, 2), /obj/item/stack/material/gold), 2, "and the gold is left on the floor")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/door_assembly_refuses_an_unsuitable_plating

/datum/unit_test/dq_p2_door/door_assembly_refuses_an_unsuitable_plating/run_gate()
	var/obj/structure/door_assembly/A = allocate(/obj/structure/door_assembly, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/stack/material/steel/steel = give_item(H, /obj/item/stack/material/steel, 4)
	click(H, A, steel)
	TEST_ASSERT_EQUAL(A.glass, 0, "steel is not a plating")
	TEST_ASSERT_EQUAL(steel.get_amount(), 4, "and none is used")

/datum/unit_test/dq_p2_door/door_assembly_welds_down_into_steel

/datum/unit_test/dq_p2_door/door_assembly_welds_down_into_steel/run_gate()
	var/obj/structure/door_assembly/A = allocate(/obj/structure/door_assembly, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null)
	click(H, A, give_welder(H))
	TEST_ASSERT(QDELETED(A), "a welder takes a loose bare assembly apart")
	TEST_ASSERT_EQUAL(sheets_on(tile(2, 2), /obj/item/stack/material/steel), 4, "into four sheets of steel")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/door_assembly_bolted_frame_cannot_be_welded_apart

/datum/unit_test/dq_p2_door/door_assembly_bolted_frame_cannot_be_welded_apart/run_gate()
	var/obj/structure/door_assembly/A = allocate(/obj/structure/door_assembly, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null)
	click(H, A, give_tool(H, /obj/item/tool/wrench))
	TEST_ASSERT(A.anchored, "bolted down")
	click(H, A, give_welder(H))
	TEST_ASSERT(!QDELETED(A), "a bolted frame is not welded apart")

/datum/unit_test/dq_p2_door/airlock_dismantles_back_to_an_assembly

/datum/unit_test/dq_p2_door/airlock_dismantles_back_to_an_assembly/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_set_power(D, FALSE)
	click(H, D, give_tool(H, /obj/item/tool/screwdriver))
	TEST_ASSERT(p2_door_panel_open(D), "the panel is open")
	p2_door_set_welded(D, TRUE)
	click(H, D, give_tool(H, /obj/item/tool/crowbar))
	TEST_ASSERT(QDELETED(D), "a crowbar takes the electronics out and the door comes apart")
	var/obj/structure/door_assembly/A = locate(/obj/structure/door_assembly) in tile(2, 2)
	TEST_ASSERT_NOTNULL(A, "an assembly is left")
	own(A)
	TEST_ASSERT(A.anchored, "bolted down")
	TEST_ASSERT_EQUAL(p2_door_assembly_state(A), 1, "wired, awaiting electronics")
	var/obj/item/airlock_electronics/board = locate(/obj/item/airlock_electronics) in tile(2, 2)
	TEST_ASSERT_NOTNULL(board, "the electronics lie on the floor")
	TEST_ASSERT(board.conf_access ~= list(ACCESS_ENGINE), "with the door's access on them")
	tidy(tile(2, 2))

// =====================================================================================================================
// FIREDOORS
// =====================================================================================================================

/datum/unit_test/dq_p2_door/firedoor_hand_use_asks_then_closes_and_opens

/datum/unit_test/dq_p2_door/firedoor_hand_use_asks_then_closes_and_opens/run_gate()
	var/obj/machinery/door/firedoor/D = make_door(/obj/machinery/door/firedoor)
	var/mob/living/carbon/human/H = make_person(null)
	TEST_ASSERT(!D.density, "a firedoor starts open")
	p2_door_click(H, D, null)
	TEST_ASSERT(!D.density, "using it asks first")
	p2_door_answer(H, TRUE)
	settle()
	TEST_ASSERT(D.density, "confirming closes it")
	p2_door_click(H, D, null)
	p2_door_answer(H, TRUE)
	settle()
	TEST_ASSERT(!D.density, "and confirming again opens it")

/datum/unit_test/dq_p2_door/firedoor_declined_prompt_leaves_it_alone

/datum/unit_test/dq_p2_door/firedoor_declined_prompt_leaves_it_alone/run_gate()
	var/obj/machinery/door/firedoor/D = make_door(/obj/machinery/door/firedoor)
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_click(H, D, null)
	p2_door_answer(H, null, TRUE)
	settle()
	TEST_ASSERT(!D.density, "cancelling the question changes nothing")

/datum/unit_test/dq_p2_door/firedoor_fire_alarm_closes_it_and_clearing_reopens

/datum/unit_test/dq_p2_door/firedoor_fire_alarm_closes_it_and_clearing_reopens/run_gate()
	var/obj/machinery/door/firedoor/D = make_door(/obj/machinery/door/firedoor)
	var/area/A = get_area(D)
	defer_cleanup(A, TYPE_PROC_REF(/area, fire_reset))
	p2_area_fire(A, TRUE)
	settle()
	TEST_ASSERT(D.density, "a fire alarm in the area closes its firedoors")
	p2_area_fire(A, FALSE)
	settle()
	TEST_ASSERT(!D.density, "and clearing it opens them")

/datum/unit_test/dq_p2_door/firedoor_welded_ignores_the_alarm

/datum/unit_test/dq_p2_door/firedoor_welded_ignores_the_alarm/run_gate()
	var/obj/machinery/door/firedoor/D = make_door(/obj/machinery/door/firedoor)
	var/mob/living/carbon/human/H = make_person(null)
	var/area/A = get_area(D)
	defer_cleanup(A, TYPE_PROC_REF(/area, fire_reset))
	click(H, D, give_welder(H))
	TEST_ASSERT(p2_firedoor_welded(D), "a welder welds an open firedoor")
	p2_area_fire(A, TRUE)
	settle()
	TEST_ASSERT(!D.density, "a welded firedoor does not answer the alarm")
	p2_area_fire(A, FALSE)
	click(H, D, give_welder(H))
	TEST_ASSERT(!p2_firedoor_welded(D), "the welder frees it again")

/datum/unit_test/dq_p2_door/firedoor_welded_refuses_hand_use

/datum/unit_test/dq_p2_door/firedoor_welded_refuses_hand_use/run_gate()
	var/obj/machinery/door/firedoor/D = make_door(/obj/machinery/door/firedoor)
	var/mob/living/carbon/human/H = make_person(null)
	p2_firedoor_set_welded(D, TRUE)
	p2_door_click(H, D, null)
	p2_door_answer(H, TRUE)
	settle()
	TEST_ASSERT(!D.density, "a welded firedoor cannot be used by hand")

/datum/unit_test/dq_p2_door/firedoor_reopened_during_an_alarm_closes_again

/datum/unit_test/dq_p2_door/firedoor_reopened_during_an_alarm_closes_again/run_gate()
	var/obj/machinery/door/firedoor/D = make_door(/obj/machinery/door/firedoor)
	var/mob/living/carbon/human/H = make_person(null)
	var/area/A = get_area(D)
	defer_cleanup(A, TYPE_PROC_REF(/area, fire_reset))
	p2_area_fire(A, TRUE)
	settle()
	TEST_ASSERT(D.density, "closed by the alarm")
	p2_door_click(H, D, null)
	p2_door_answer(H, TRUE)
	test_time(3 SECONDS)
	TEST_ASSERT(!D.density, "someone opens it by hand")
	TEST_ASSERT(LAZYLEN(D.users_to_open), "and it remembers who")
	settle()
	TEST_ASSERT(D.density, "with the alarm still on it closes itself again")

/datum/unit_test/dq_p2_door/firedoor_powered_resists_a_crowbar_and_unpowered_does_not

/datum/unit_test/dq_p2_door/firedoor_powered_resists_a_crowbar_and_unpowered_does_not/run_gate()
	var/obj/machinery/door/firedoor/D = make_door(/obj/machinery/door/firedoor)
	var/mob/living/carbon/human/H = make_person(null)
	var/area/A = get_area(D)
	defer_cleanup(A, TYPE_PROC_REF(/area, fire_reset))
	p2_area_fire(A, TRUE)
	settle()
	TEST_ASSERT(D.density, "closed by the alarm")
	var/obj/item/crowbar = give_tool(H, /obj/item/tool/crowbar)
	click(H, D, crowbar)
	TEST_ASSERT(D.density, "a crowbar does not force a powered firedoor")
	p2_door_set_power(D, FALSE)
	click(H, D, crowbar)
	TEST_ASSERT(!D.density, "it forces an unpowered one open")

/datum/unit_test/dq_p2_door/firedoor_welded_resists_a_crowbar

/datum/unit_test/dq_p2_door/firedoor_welded_resists_a_crowbar/run_gate()
	var/obj/machinery/door/firedoor/D = make_door(/obj/machinery/door/firedoor)
	var/mob/living/carbon/human/H = make_person(null)
	var/area/A = get_area(D)
	defer_cleanup(A, TYPE_PROC_REF(/area, fire_reset))
	p2_area_fire(A, TRUE)
	settle()
	click(H, D, give_welder(H))
	TEST_ASSERT(p2_firedoor_welded(D), "welded closed")
	p2_door_set_power(D, FALSE)
	click(H, D, give_tool(H, /obj/item/tool/crowbar))
	TEST_ASSERT(D.density, "a crowbar cannot force a welded firedoor")

/datum/unit_test/dq_p2_door/firedoor_screwdriver_opens_the_hatch_only_when_closed

/datum/unit_test/dq_p2_door/firedoor_screwdriver_opens_the_hatch_only_when_closed/run_gate()
	var/obj/machinery/door/firedoor/D = make_door(/obj/machinery/door/firedoor)
	var/mob/living/carbon/human/H = make_person(null)
	var/area/A = get_area(D)
	defer_cleanup(A, TYPE_PROC_REF(/area, fire_reset))
	var/obj/item/driver = give_tool(H, /obj/item/tool/screwdriver)
	click(H, D, driver)
	TEST_ASSERT(!p2_firedoor_hatch_open(D), "an open firedoor has no hatch to open")
	p2_area_fire(A, TRUE)
	settle()
	click(H, D, driver)
	TEST_ASSERT(p2_firedoor_hatch_open(D), "a closed one does")
	click(H, D, driver)
	TEST_ASSERT(!p2_firedoor_hatch_open(D), "and the screwdriver closes it again")

/datum/unit_test/dq_p2_door/firedoor_welded_with_open_hatch_comes_apart

/datum/unit_test/dq_p2_door/firedoor_welded_with_open_hatch_comes_apart/run_gate()
	var/obj/machinery/door/firedoor/D = make_door(/obj/machinery/door/firedoor)
	var/mob/living/carbon/human/H = make_person(null)
	var/area/A = get_area(D)
	defer_cleanup(A, TYPE_PROC_REF(/area, fire_reset))
	p2_area_fire(A, TRUE)
	settle()
	click(H, D, give_welder(H))
	click(H, D, give_tool(H, /obj/item/tool/screwdriver))
	TEST_ASSERT(p2_firedoor_hatch_open(D), "hatch open")
	click(H, D, give_tool(H, /obj/item/tool/crowbar))
	TEST_ASSERT(QDELETED(D), "a crowbar takes the electronics out")
	var/obj/structure/firedoor_assembly/F = locate(/obj/structure/firedoor_assembly) in tile(2, 2)
	TEST_ASSERT_NOTNULL(F, "an assembly stands in its place")
	own(F)
	TEST_ASSERT(F.anchored && p2_firedoor_assembly_wired(F), "bolted and wired")
	TEST_ASSERT_NOTNULL(locate(/obj/item/circuitboard) in tile(2, 2), "the circuit board lies on the floor")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/firedoor_prompt_says_what_it_would_do

/datum/unit_test/dq_p2_door/firedoor_prompt_says_what_it_would_do/run_gate()
	var/obj/machinery/door/firedoor/D = make_door(/obj/machinery/door/firedoor)
	var/mob/living/carbon/human/H = make_person(null)
	var/area/A = get_area(D)
	defer_cleanup(A, TYPE_PROC_REF(/area, fire_reset))
	p2_door_click(H, D, null)
	var/datum/prompt/P = SSrequests.open_for(H)
	TEST_ASSERT_NOTNULL(P, "using it asks")
	TEST_ASSERT(findtext(P.question, "close"), "an open firedoor asks about closing")
	TEST_ASSERT(!findtext(P.question, "accountable"), "and says nothing of blame")
	p2_door_answer(H, null, TRUE)
	p2_area_fire(A, TRUE)
	settle()
	TEST_ASSERT(D.density, "closed by the alarm")
	p2_door_click(H, D, null)
	P = SSrequests.open_for(H)
	TEST_ASSERT_NOTNULL(P, "using it asks again")
	TEST_ASSERT(findtext(P.question, "open"), "a shut firedoor asks about opening")
	TEST_ASSERT(findtext(P.question, "accountable"), "and in an alarm, who is to blame for it")
	p2_door_answer(H, null, TRUE)

/datum/unit_test/dq_p2_door/firedoor_silicon_uses_it_through_the_prompt

/datum/unit_test/dq_p2_door/firedoor_silicon_uses_it_through_the_prompt/run_gate()
	var/obj/machinery/door/firedoor/D = make_door(/obj/machinery/door/firedoor)
	var/mob/living/silicon/ai/AI = make_ai()
	D.silicon_use(AI)
	p2_door_answer(AI, TRUE)
	settle()
	TEST_ASSERT(D.density, "an AI closes a firedoor through the same question")

/datum/unit_test/dq_p2_door/firedoor_second_prier_is_refused_while_the_first_works

/datum/unit_test/dq_p2_door/firedoor_second_prier_is_refused_while_the_first_works/run_gate()
	var/obj/machinery/door/firedoor/D = make_door(/obj/machinery/door/firedoor)
	var/mob/living/carbon/human/H = make_person(null)
	var/mob/living/carbon/human/other = make_person(null, tile(3, 3))
	var/area/A = get_area(D)
	defer_cleanup(A, TYPE_PROC_REF(/area, fire_reset))
	p2_area_fire(A, TRUE)
	settle()
	p2_door_set_power(D, FALSE)
	var/obj/item/crowbar = give_tool(H, /obj/item/tool/crowbar)
	crowbar.toolspeed = 1
	var/obj/item/second = give_tool(other, /obj/item/tool/crowbar)
	second.toolspeed = 1
	p2_door_click(H, D, crowbar)
	TEST_ASSERT(op_claimed(D), "a crowbar at work claims the door")
	p2_door_click(other, D, second)
	test_time(1 SECOND)
	TEST_ASSERT(D.density, "nothing has given yet")
	test_time(5 SECONDS)
	TEST_ASSERT(!D.density, "the first one forced it")
	TEST_ASSERT(!op_claimed(D), "and the claim ended with the work")

/datum/unit_test/dq_p2_door/firedoor_strong_animal_forces_a_dead_one

/datum/unit_test/dq_p2_door/firedoor_strong_animal_forces_a_dead_one/run_gate()
	var/obj/machinery/door/firedoor/D = make_door(/obj/machinery/door/firedoor)
	var/area/A = get_area(D)
	defer_cleanup(A, TYPE_PROC_REF(/area, fire_reset))
	p2_area_fire(A, TRUE)
	settle()
	p2_door_set_power(D, FALSE)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, tile(3, 2))
	generic_hit(D, M, 1)
	test_time(3 SECONDS)
	TEST_ASSERT(D.density, "a weak animal strains for nothing")
	generic_hit(D, M, 50)
	test_time(3 SECONDS)
	TEST_ASSERT(!D.density, "a strong one forces it open")

/datum/unit_test/dq_p2_door/firedoor_assembly_builds_a_firedoor

/datum/unit_test/dq_p2_door/firedoor_assembly_builds_a_firedoor/run_gate()
	var/obj/structure/firedoor_assembly/F = allocate(/obj/structure/firedoor_assembly, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/circuitboard/airalarm/board = allocate(/obj/item/circuitboard/airalarm, H.loc)
	var/obj/item/stack/cable_coil/cable = give_item(H, /obj/item/stack/cable_coil, 5)
	click(H, F, cable)
	TEST_ASSERT(!p2_firedoor_assembly_wired(F), "a loose assembly cannot be wired")
	click(H, F, give_tool(H, /obj/item/tool/wrench))
	TEST_ASSERT(F.anchored, "a wrench bolts it down")
	click(H, F, cable)
	TEST_ASSERT(p2_firedoor_assembly_wired(F), "now cable wires it")
	click(H, F, hold(H, board))
	TEST_ASSERT(QDELETED(F), "the circuit board finishes it")
	var/obj/machinery/door/firedoor/D = locate(/obj/machinery/door/firedoor) in tile(2, 2)
	TEST_ASSERT_NOTNULL(D, "a firedoor stands where the assembly was")
	own(D)
	TEST_ASSERT(!D.glass, "a plain one")

/datum/unit_test/dq_p2_door/firedoor_assembly_with_glass_builds_a_glass_firedoor

/datum/unit_test/dq_p2_door/firedoor_assembly_with_glass_builds_a_glass_firedoor/run_gate()
	var/obj/structure/firedoor_assembly/F = allocate(/obj/structure/firedoor_assembly, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/circuitboard/airalarm/board = allocate(/obj/item/circuitboard/airalarm, H.loc)
	click(H, F, give_item(H, /obj/item/stack/material/glass/reinforced, 2))
	TEST_ASSERT(F.glass, "reinforced glass windows the assembly")
	click(H, F, give_tool(H, /obj/item/tool/wrench))
	click(H, F, give_item(H, /obj/item/stack/cable_coil, 5))
	click(H, F, hold(H, board))
	TEST_ASSERT(QDELETED(F), "finished")
	var/obj/machinery/door/firedoor/D = locate(/obj/machinery/door/firedoor) in tile(2, 2)
	TEST_ASSERT_NOTNULL(D, "a firedoor stands where the assembly was")
	own(D)
	TEST_ASSERT(D.glass, "a glass one")

/datum/unit_test/dq_p2_door/firedoor_assembly_steps_can_be_undone

/datum/unit_test/dq_p2_door/firedoor_assembly_steps_can_be_undone/run_gate()
	var/obj/structure/firedoor_assembly/F = allocate(/obj/structure/firedoor_assembly, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null)
	click(H, F, give_tool(H, /obj/item/tool/wrench))
	click(H, F, give_item(H, /obj/item/stack/cable_coil, 5))
	TEST_ASSERT(p2_firedoor_assembly_wired(F), "wired")
	click(H, F, give_tool(H, /obj/item/tool/wirecutters))
	TEST_ASSERT(!p2_firedoor_assembly_wired(F), "wirecutters strip it")
	click(H, F, give_item(H, /obj/item/stack/material/glass/reinforced, 2))
	TEST_ASSERT(F.glass, "glazed")
	click(H, F, give_welder(H))
	TEST_ASSERT(!F.glass, "a welder cuts the glass out")
	click(H, F, give_tool(H, /obj/item/tool/wrench))
	TEST_ASSERT(!F.anchored, "a wrench frees it")
	click(H, F, give_welder(H))
	TEST_ASSERT(QDELETED(F), "a welder takes the loose bare assembly apart")
	TEST_ASSERT_EQUAL(sheets_on(tile(2, 2), /obj/item/stack/material/steel), 2, "into two sheets of steel")
	tidy(tile(2, 2))

// =====================================================================================================================
// BLAST DOORS
// =====================================================================================================================

/datum/unit_test/dq_p2_door/blast_door_button_opens_and_closes_doors_with_its_id

/datum/unit_test/dq_p2_door/blast_door_button_opens_and_closes_doors_with_its_id/run_gate()
	var/obj/machinery/door/blast/B = make_door(/obj/machinery/door/blast/regular/p2_test)
	var/obj/machinery/door/blast/other = allocate(/obj/machinery/door/blast/regular, tile(1, 2))
	p2_door_set_power(other, TRUE)
	var/obj/machinery/button/remote/blast_door/button = allocate(/obj/machinery/button/remote/blast_door/p2_test, tile(4, 2))
	p2_door_set_power(button, TRUE)
	var/mob/living/carbon/human/H = make_person(null, tile(4, 3))
	click(H, button, null)
	TEST_ASSERT(!B.density, "the button opens the blast door with its id")
	TEST_ASSERT(other.density, "and leaves the one with another id alone")
	click(H, button, null)
	TEST_ASSERT(B.density, "pressing it again closes it")

/datum/unit_test/dq_p2_door/blast_door_ignores_hands_and_ids

/datum/unit_test/dq_p2_door/blast_door_ignores_hands_and_ids/run_gate()
	var/obj/machinery/door/blast/B = make_door(/obj/machinery/door/blast/regular)
	var/mob/living/carbon/human/H = make_person(list(ACCESS_CAPTAIN))
	click(H, B, null)
	TEST_ASSERT(B.density, "a blast door does not open by hand, whatever the ID")
	H.Bump(B)
	settle()
	TEST_ASSERT(B.density, "nor by a bump")

/datum/unit_test/dq_p2_door/blast_door_dead_button_does_nothing

/datum/unit_test/dq_p2_door/blast_door_dead_button_does_nothing/run_gate()
	var/obj/machinery/door/blast/B = make_door(/obj/machinery/door/blast/regular/p2_test)
	var/obj/machinery/button/remote/blast_door/button = allocate(/obj/machinery/button/remote/blast_door/p2_test, tile(4, 2))
	p2_door_set_power(button, FALSE)
	var/mob/living/carbon/human/H = make_person(null, tile(4, 3))
	click(H, button, null)
	TEST_ASSERT(B.density, "a button with no power does not open the door")

/datum/unit_test/dq_p2_door/blast_door_powered_resists_a_crowbar_and_unpowered_does_not

/datum/unit_test/dq_p2_door/blast_door_powered_resists_a_crowbar_and_unpowered_does_not/run_gate()
	var/obj/machinery/door/blast/B = make_door(/obj/machinery/door/blast/regular)
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/crowbar = give_tool(H, /obj/item/tool/crowbar)
	click(H, B, crowbar)
	TEST_ASSERT(B.density, "a powered blast door resists a crowbar")
	p2_door_set_power(B, FALSE)
	click(H, B, crowbar)
	TEST_ASSERT(!B.density, "an unpowered one gives way")
	click(H, B, crowbar)
	TEST_ASSERT(B.density, "and can be forced shut again")

/datum/unit_test/dq_p2_door/blast_door_broken_one_gives_way_to_a_crowbar

/datum/unit_test/dq_p2_door/blast_door_broken_one_gives_way_to_a_crowbar/run_gate()
	var/obj/machinery/door/blast/B = make_door(/obj/machinery/door/blast/regular)
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/crowbar = give_tool(H, /obj/item/tool/crowbar)
	B.take_damage(B.max_integrity * 0.9, BRUTE, MELEE)
	TEST_ASSERT(B.has_stat(BROKEN), "broken")
	click(H, B, crowbar)
	TEST_ASSERT(!B.density, "a broken blast door gives way to a crowbar")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/blast_door_strike_damages_only_with_enough_force

/datum/unit_test/dq_p2_door/blast_door_strike_damages_only_with_enough_force/run_gate()
	var/obj/machinery/door/blast/B = make_door(/obj/machinery/door/blast/regular)
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/bar = give_item(H, /obj/item/pen)
	H.set_combat_mode(TRUE)
	bar.force = 5
	var/before = B.get_integrity()
	click(H, B, bar)
	TEST_ASSERT_EQUAL(B.get_integrity(), before, "a weak hit leaves no mark")
	bar.force = 60
	click(H, B, bar)
	TEST_ASSERT(B.get_integrity() < before, "a hard one damages it")

/datum/unit_test/dq_p2_door/blast_door_plasteel_repairs_it

/datum/unit_test/dq_p2_door/blast_door_plasteel_repairs_it/run_gate()
	var/obj/machinery/door/blast/B = make_door(/obj/machinery/door/blast/regular)
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/stack/material/plasteel/sheets = give_item(H, /obj/item/stack/material/plasteel, 5)
	click(H, B, sheets)
	TEST_ASSERT_EQUAL(sheets.get_amount(), 5, "an undamaged door takes no sheets")
	B.take_damage(100, BRUTE, MELEE)
	TEST_ASSERT(B.get_integrity() < B.max_integrity, "damaged")
	click(H, B, sheets)
	TEST_ASSERT_EQUAL(B.get_integrity(), B.max_integrity, "plasteel repairs it fully")
	TEST_ASSERT(sheets.get_amount() < 5, "using sheets")

/datum/unit_test/dq_p2_door/blast_door_repair_needs_enough_sheets

/datum/unit_test/dq_p2_door/blast_door_repair_needs_enough_sheets/run_gate()
	var/obj/machinery/door/blast/B = make_door(/obj/machinery/door/blast/regular)
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/stack/material/plasteel/sheets = give_item(H, /obj/item/stack/material/plasteel, 1)
	B.take_damage(500, BRUTE, MELEE)
	var/before = B.get_integrity()
	click(H, B, sheets)
	TEST_ASSERT_EQUAL(B.get_integrity(), before, "one sheet is not enough for a wrecked door")
	TEST_ASSERT_EQUAL(sheets.get_amount(), 1, "and it is not used")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/blast_door_strong_animal_forces_a_dead_one

/datum/unit_test/dq_p2_door/blast_door_strong_animal_forces_a_dead_one/run_gate()
	var/obj/machinery/door/blast/B = make_door(/obj/machinery/door/blast/regular)
	p2_door_set_power(B, FALSE)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, tile(3, 2))
	generic_hit(B, M, 1)
	test_time(6 SECONDS)
	TEST_ASSERT(B.density, "a weak animal strains for nothing")
	generic_hit(B, M, 50)
	test_time(6 SECONDS)
	TEST_ASSERT(!B.density, "a strong one forces it open")

/datum/unit_test/dq_p2_door/blast_door_swallows_a_held_thing

/datum/unit_test/dq_p2_door/blast_door_swallows_a_held_thing/run_gate()
	var/obj/machinery/door/blast/B = make_door(/obj/machinery/door/blast/regular)
	var/mob/living/carbon/human/H = make_person(list(ACCESS_CAPTAIN))
	var/obj/item/pen = give_item(H, /obj/item/pen)
	var/before = B.get_integrity()
	click(H, B, pen)
	TEST_ASSERT(B.density, "a pen does not open a blast door")
	TEST_ASSERT_EQUAL(B.get_integrity(), before, "and does not hurt it")

/datum/unit_test/dq_p2_door/blast_door_emag_doubles_its_throw

/datum/unit_test/dq_p2_door/blast_door_emag_doubles_its_throw/run_gate()
	var/obj/machinery/door/blast/B = make_door(/obj/machinery/door/blast/regular)
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/card/emag/emag = give_item(H, /obj/item/card/emag)
	var/uses = emag.uses
	TEST_ASSERT_EQUAL(B.multiplier, 1, "a blast door throws normally")
	click(H, B, emag)
	TEST_ASSERT(p2_door_emagged(B), "a sequencer marks it emagged")
	TEST_ASSERT_EQUAL(B.multiplier, 2, "and doubles its throw")
	TEST_ASSERT_EQUAL(emag.uses, uses - 1, "spending one charge")
	click(H, B, emag)
	TEST_ASSERT_EQUAL(emag.uses, uses - 1, "a second swipe spends nothing")

/datum/unit_test/dq_p2_door/blast_door_crushes_on_closing

/datum/unit_test/dq_p2_door/blast_door_crushes_on_closing/run_gate()
	var/obj/machinery/door/blast/B = make_door(/obj/machinery/door/blast/regular/p2_test)
	var/obj/machinery/button/remote/blast_door/button = allocate(/obj/machinery/button/remote/blast_door/p2_test, tile(4, 2))
	p2_door_set_power(button, TRUE)
	var/mob/living/carbon/human/presser = make_person(null, tile(4, 3))
	click(presser, button, null)
	TEST_ASSERT(!B.density, "open")
	var/mob/living/carbon/human/H = make_person(null, tile(2, 2))
	var/before = H.vitality()
	var/door_before = B.get_integrity()
	click(presser, button, null)
	TEST_ASSERT(B.density, "closed")
	TEST_ASSERT(H.vitality() < before, "closing on someone crushes them")
	TEST_ASSERT(B.get_integrity() < door_before, "and costs the door a little")
	tidy(tile(2, 2))

// =====================================================================================================================
// WINDOORS
// =====================================================================================================================

/datum/unit_test/dq_p2_door/windoor_opens_and_closes_for_access

/datum/unit_test/dq_p2_door/windoor_opens_and_closes_for_access/run_gate()
	var/obj/machinery/door/window/D = make_door(/obj/machinery/door/window, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(list(ACCESS_ENGINE), tile(1, 2))
	TEST_ASSERT(D.density, "a windoor starts closed")
	click(H, D, null)
	TEST_ASSERT(!D.density, "an ID with the access opens it")
	click(H, D, null)
	TEST_ASSERT(D.density, "and the same click closes it")

/datum/unit_test/dq_p2_door/windoor_denies_without_access

/datum/unit_test/dq_p2_door/windoor_denies_without_access/run_gate()
	var/obj/machinery/door/window/D = make_door(/obj/machinery/door/window, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(list(ACCESS_SECURITY), tile(1, 2))
	click(H, D, null)
	TEST_ASSERT(D.density, "the wrong access does not open it")
	H.Bump(D)
	settle()
	TEST_ASSERT(D.density, "nor does a bump")

/datum/unit_test/dq_p2_door/windoor_bump_opens_then_closes_itself

/datum/unit_test/dq_p2_door/windoor_bump_opens_then_closes_itself/run_gate()
	var/obj/machinery/door/window/D = make_door(/obj/machinery/door/window, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(list(ACCESS_ENGINE), tile(1, 2))
	H.Bump(D)
	test_time(1.5 SECONDS)
	TEST_ASSERT(!D.density, "walking into a windoor with access opens it")
	settle()
	TEST_ASSERT(D.density, "and it swings shut by itself afterwards")

/datum/unit_test/dq_p2_door/windoor_emag_opens_it_for_good

/datum/unit_test/dq_p2_door/windoor_emag_opens_it_for_good/run_gate()
	var/obj/machinery/door/window/D = make_door(/obj/machinery/door/window, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(null, tile(1, 2))
	var/obj/item/card/emag/emag = give_item(H, /obj/item/card/emag)
	click(H, D, emag)
	TEST_ASSERT(!D.density, "a sequencer opens the windoor")
	var/mob/living/carbon/human/engineer = make_person(list(ACCESS_ENGINE), tile(3, 3))
	click(engineer, D, null)
	TEST_ASSERT(!D.density, "and it will not close again")

/datum/unit_test/dq_p2_door/windoor_hit_damages_it

/datum/unit_test/dq_p2_door/windoor_hit_damages_it/run_gate()
	var/obj/machinery/door/window/D = make_door(/obj/machinery/door/window, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(null, tile(1, 2))
	var/obj/item/bar = give_item(H, /obj/item/pen)
	bar.force = 20
	H.set_combat_mode(TRUE)
	var/before = D.get_integrity()
	click(H, D, bar)
	TEST_ASSERT(D.get_integrity() < before, "a hit damages the windoor")
	TEST_ASSERT(!QDELETED(D), "but one hit does not break it")

/datum/unit_test/dq_p2_door/windoor_shatters_when_destroyed

/datum/unit_test/dq_p2_door/windoor_shatters_when_destroyed/run_gate()
	var/obj/machinery/door/window/D = make_door(/obj/machinery/door/window, list(ACCESS_ENGINE))
	D.take_damage(D.max_integrity * 2, BRUTE, MELEE)
	settle()
	TEST_ASSERT(QDELETED(D), "a destroyed windoor shatters")
	TEST_ASSERT_EQUAL(length(turf_contents_of_type(tile(2, 2), /obj/item/material/shard)), 2, "leaving two shards")
	var/obj/item/airlock_electronics/board = locate(/obj/item/airlock_electronics) in tile(2, 2)
	TEST_ASSERT_NOTNULL(board, "and its electronics")
	TEST_ASSERT(board.conf_access ~= list(ACCESS_ENGINE), "with the access it had")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/windoor_welder_repairs_damage

/datum/unit_test/dq_p2_door/windoor_welder_repairs_damage/run_gate()
	var/obj/machinery/door/window/D = make_door(/obj/machinery/door/window, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(null, tile(1, 2))
	D.take_damage(50, BRUTE, MELEE)
	TEST_ASSERT(D.get_integrity() < D.max_integrity, "damaged")
	click(H, D, give_welder(H))
	TEST_ASSERT_EQUAL(D.get_integrity(), D.max_integrity, "a welder repairs it")

/datum/unit_test/dq_p2_door/windoor_open_one_pries_out_into_an_assembly

/datum/unit_test/dq_p2_door/windoor_open_one_pries_out_into_an_assembly/run_gate()
	var/obj/machinery/door/window/D = make_door(/obj/machinery/door/window, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(list(ACCESS_ENGINE), tile(1, 2))
	var/obj/item/crowbar = give_tool(H, /obj/item/tool/crowbar)
	click(H, D, crowbar)
	TEST_ASSERT(!QDELETED(D), "a closed windoor cannot be pried out")
	click(H, D, null) // open it
	TEST_ASSERT(!D.density, "open")
	click(H, D, crowbar)
	TEST_ASSERT(QDELETED(D), "an open one comes out of its frame")
	var/obj/structure/windoor_assembly/A = locate(/obj/structure/windoor_assembly) in tile(2, 2)
	TEST_ASSERT_NOTNULL(A, "an assembly is left")
	own(A)
	TEST_ASSERT(A.anchored, "bolted down")
	TEST_ASSERT_EQUAL(A.sprite_state(), "02", "wired and with its electronics")
	TEST_ASSERT(A.electronics && (A.electronics.conf_access ~= list(ACCESS_ENGINE)), "which carry the access")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/windoor_assembly_builds_a_windoor

/datum/unit_test/dq_p2_door/windoor_assembly_builds_a_windoor/run_gate()
	var/obj/structure/windoor_assembly/A = allocate(/obj/structure/windoor_assembly, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null, tile(1, 2))
	var/obj/item/airlock_electronics/board = allocate(/obj/item/airlock_electronics, H.loc)
	board.conf_access = list(ACCESS_ENGINE)
	TEST_ASSERT(!A.anchored, "a new assembly is loose")
	click(H, A, give_tool(H, /obj/item/tool/wrench))
	TEST_ASSERT(A.anchored, "a wrench bolts it down")
	var/obj/item/stack/cable_coil/cable = give_item(H, /obj/item/stack/cable_coil, 5)
	click(H, A, cable)
	TEST_ASSERT_EQUAL(A.sprite_state(), "02", "cable wires it")
	TEST_ASSERT_EQUAL(cable.get_amount(), 4, "using one length")
	click(H, A, hold(H, board))
	TEST_ASSERT_EQUAL(A.electronics, board, "electronics go in")
	click(H, A, give_tool(H, /obj/item/tool/crowbar))
	TEST_ASSERT(QDELETED(A), "a crowbar finishes the windoor")
	var/obj/machinery/door/window/D = locate(/obj/machinery/door/window) in tile(2, 2)
	TEST_ASSERT_NOTNULL(D, "a windoor stands where the assembly was")
	own(D)
	TEST_ASSERT(D.density, "closed")
	TEST_ASSERT(D.req_access ~= list(ACCESS_ENGINE), "with the access from its electronics")
	TEST_ASSERT_EQUAL(D.electronics, board, "which sit inside it")
	p2_door_set_power(D, TRUE)
	var/mob/living/carbon/human/engineer = make_person(list(ACCESS_ENGINE), tile(3, 3))
	click(engineer, D, null)
	TEST_ASSERT(!D.density, "an engineer opens it")

/datum/unit_test/dq_p2_door/windoor_assembly_steps_can_be_undone

/datum/unit_test/dq_p2_door/windoor_assembly_steps_can_be_undone/run_gate()
	var/obj/structure/windoor_assembly/A = allocate(/obj/structure/windoor_assembly, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null, tile(1, 2))
	var/obj/item/airlock_electronics/board = allocate(/obj/item/airlock_electronics, H.loc)
	click(H, A, give_tool(H, /obj/item/tool/wrench))
	click(H, A, give_item(H, /obj/item/stack/cable_coil, 5))
	click(H, A, hold(H, board))
	TEST_ASSERT_EQUAL(A.electronics, board, "electronics in")
	click(H, A, give_tool(H, /obj/item/tool/screwdriver))
	TEST_ASSERT_NULL(A.electronics, "a screwdriver takes them out")
	TEST_ASSERT_EQUAL(board.loc, tile(2, 2), "onto the floor")
	click(H, A, give_tool(H, /obj/item/tool/wirecutters))
	TEST_ASSERT_EQUAL(A.sprite_state(), "01", "wirecutters strip the wiring")
	click(H, A, give_tool(H, /obj/item/tool/wrench))
	TEST_ASSERT(!A.anchored, "a wrench frees it")
	click(H, A, give_welder(H))
	TEST_ASSERT(QDELETED(A), "a welder takes it apart")
	TEST_ASSERT_EQUAL(sheets_on(tile(2, 2), /obj/item/stack/material/glass), 2, "into two sheets of glass")
	tidy(tile(2, 2))
	tidy(tile(1, 2))

/datum/unit_test/dq_p2_door/windoor_assembly_without_electronics_cannot_be_finished

/datum/unit_test/dq_p2_door/windoor_assembly_without_electronics_cannot_be_finished/run_gate()
	var/obj/structure/windoor_assembly/A = allocate(/obj/structure/windoor_assembly, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null, tile(1, 2))
	click(H, A, give_tool(H, /obj/item/tool/wrench))
	click(H, A, give_item(H, /obj/item/stack/cable_coil, 5))
	click(H, A, give_tool(H, /obj/item/tool/crowbar))
	TEST_ASSERT(!QDELETED(A), "a crowbar does not finish a windoor with no electronics")

/datum/unit_test/dq_p2_door/windoor_brig_door_wants_security_access

/datum/unit_test/dq_p2_door/windoor_brig_door_wants_security_access/run_gate()
	var/obj/machinery/door/window/brigdoor/D = make_door(/obj/machinery/door/window/brigdoor)
	var/mob/living/carbon/human/guard = make_person(list(ACCESS_SECURITY), tile(1, 2))
	var/mob/living/carbon/human/medic = make_person(list(ACCESS_MEDICAL), tile(3, 3))
	click(medic, D, null)
	TEST_ASSERT(D.density, "a brig door refuses a medic")
	click(guard, D, null)
	TEST_ASSERT(!D.density, "and opens for security")

// =====================================================================================================================
// REMOTE BUTTONS
// =====================================================================================================================

/// A button at (4, 2) with a person next to it, and a blast door of its id.
/datum/unit_test/dq_p2_door/proc/button_setup(button_type = /obj/machinery/button/remote/blast_door/p2_test, list/access)
	var/obj/machinery/door/blast/B = make_door(/obj/machinery/door/blast/regular/p2_test)
	var/obj/machinery/button/remote/button = allocate(button_type, tile(4, 2))
	p2_door_set_power(button, TRUE)
	if(access)
		button.req_access = access
	return list(B, button)

/datum/unit_test/dq_p2_door/button_access_lock_keeps_out_strangers

/datum/unit_test/dq_p2_door/button_access_lock_keeps_out_strangers/run_gate()
	var/list/set_up = button_setup(access = list(ACCESS_ENGINE))
	var/obj/machinery/door/blast/B = set_up[1]
	var/obj/machinery/button/remote/button = set_up[2]
	var/mob/living/carbon/human/stranger = make_person(null, tile(4, 3))
	var/mob/living/carbon/human/engineer = make_person(list(ACCESS_ENGINE), tile(5, 2))
	click(stranger, button, null)
	TEST_ASSERT(B.density, "a stranger cannot work a locked button")
	click(engineer, button, null)
	TEST_ASSERT(!B.density, "an engineer can")

/datum/unit_test/dq_p2_door/button_is_pressed_by_any_held_thing

/datum/unit_test/dq_p2_door/button_is_pressed_by_any_held_thing/run_gate()
	var/list/set_up = button_setup()
	var/obj/machinery/door/blast/B = set_up[1]
	var/obj/machinery/button/remote/button = set_up[2]
	var/mob/living/carbon/human/H = make_person(null, tile(4, 3))
	click(H, button, give_item(H, /obj/item/pen))
	TEST_ASSERT(!B.density, "a pen presses a remote button")

/datum/unit_test/dq_p2_door/button_sequencer_scorches_the_lock_off

/datum/unit_test/dq_p2_door/button_sequencer_scorches_the_lock_off/run_gate()
	var/list/set_up = button_setup(access = list(ACCESS_ENGINE))
	var/obj/machinery/door/blast/B = set_up[1]
	var/obj/machinery/button/remote/button = set_up[2]
	var/mob/living/carbon/human/H = make_person(null, tile(4, 3))
	var/obj/item/card/emag/emag = give_item(H, /obj/item/card/emag)
	click(H, button, emag)
	TEST_ASSERT(!LAZYLEN(button.req_access), "the sequencer burns the lock off")
	click(H, button, null)
	TEST_ASSERT(!B.density, "and a stranger works it")

/datum/unit_test/dq_p2_door/button_silicon_presses_it_from_afar

/datum/unit_test/dq_p2_door/button_silicon_presses_it_from_afar/run_gate()
	var/list/set_up = button_setup()
	var/obj/machinery/door/blast/B = set_up[1]
	var/obj/machinery/button/remote/button = set_up[2]
	var/mob/living/silicon/ai/AI = make_ai()
	test_op_handler(button, "silicon_pressed", AI)
	settle()
	TEST_ASSERT(!B.density, "an AI works a remote button")

/datum/unit_test/dq_p2_door/button_single_use_is_spent

/datum/unit_test/dq_p2_door/button_single_use_is_spent/run_gate()
	var/list/set_up = button_setup(/obj/machinery/button/remote/blast_door/single_use/p2_test)
	var/obj/machinery/door/blast/B = set_up[1]
	var/obj/machinery/button/remote/button = set_up[2]
	var/mob/living/carbon/human/H = make_person(null, tile(4, 3))
	click(H, button, null)
	TEST_ASSERT(!B.density, "the first press opens it")
	click(H, button, null)
	TEST_ASSERT(!B.density, "a spent button does nothing")

/datum/unit_test/dq_p2_door/driver_button_wants_an_id_or_a_pda

/datum/unit_test/dq_p2_door/driver_button_wants_an_id_or_a_pda/run_gate()
	var/list/set_up = button_setup(/obj/machinery/button/remote/driver/p2_test)
	var/obj/machinery/door/blast/B = set_up[1]
	var/obj/machinery/button/remote/button = set_up[2]
	var/mob/living/carbon/human/H = make_person(null, tile(4, 3))
	click(H, button, give_item(H, /obj/item/pen))
	TEST_ASSERT(B.density, "a pen does not press the mass driver button")
	p2_door_click(H, button, give_item(H, /obj/item/card/id))
	test_time(1 SECOND)
	TEST_ASSERT(!B.density, "an ID does")
	test_time(8 SECONDS)
	TEST_ASSERT(B.density, "and the doors shut again after the launch")

/datum/unit_test/dq_p2_door/driver_button_id_is_set_with_a_multitool

/datum/unit_test/dq_p2_door/driver_button_id_is_set_with_a_multitool/run_gate()
	var/list/set_up = button_setup(/obj/machinery/button/remote/driver/p2_test)
	var/obj/machinery/door/blast/B = set_up[1]
	var/obj/machinery/button/remote/driver/button = set_up[2]
	var/mob/living/carbon/human/H = make_person(null, tile(4, 3))
	p2_door_click(H, button, give_tool(H, /obj/item/multitool))
	p2_door_answer(H, 4242)
	settle()
	TEST_ASSERT_EQUAL(button.id, 4242, "the multitool sets the id")
	p2_door_click(H, button, give_item(H, /obj/item/card/id))
	test_time(1 SECOND)
	TEST_ASSERT(B.density, "and the old door no longer answers it")

// =====================================================================================================================
// AIRLOCK SENSORS AND ACCESS BUTTONS
// =====================================================================================================================

/// Hears what a sensor or a button sends on the airlock frequency.
/obj/p2_radio_listener
	var/list/heard

/obj/p2_radio_listener/receive_signal(datum/signal/signal)
	LAZYADD(heard, list(signal.data.Copy()))

/// A listener on the airlock frequency, next to where a sensor or a button is put at (2, 2).
/datum/unit_test/dq_p2_door/proc/radio_listener()
	var/obj/p2_radio_listener/L = allocate(/obj/p2_radio_listener, tile(1, 2))
	SSradio.add_object(L, AIRLOCK_FREQ, RADIO_AIRLOCK)
	return L

/datum/unit_test/dq_p2_door/access_button_sends_its_command_to_whoever_has_access

/datum/unit_test/dq_p2_door/access_button_sends_its_command_to_whoever_has_access/run_gate()
	var/obj/p2_radio_listener/L = radio_listener()
	var/obj/machinery/access_button/airlock_interior/button = allocate(/obj/machinery/access_button/airlock_interior, tile(2, 2))
	p2_door_set_power(button, TRUE)
	button.master_tag = "p2_controller"
	button.req_access = list(ACCESS_ENGINE)
	var/mob/living/carbon/human/stranger = make_person(null, tile(3, 2))
	var/mob/living/carbon/human/engineer = make_person(list(ACCESS_ENGINE), tile(3, 3))
	click(stranger, button, null)
	TEST_ASSERT(!LAZYLEN(L.heard), "a stranger's press sends nothing")
	click(engineer, button, null)
	TEST_ASSERT_EQUAL(LAZYLEN(L.heard), 1, "an engineer's press sends one signal")
	var/list/signal = L.heard[1]
	TEST_ASSERT_EQUAL(signal["tag"], "p2_controller", "to its controller")
	TEST_ASSERT_EQUAL(signal["command"], "cycle_interior", "with its command")
	SSradio.remove_object(L, AIRLOCK_FREQ)

/datum/unit_test/dq_p2_door/access_button_takes_a_swiped_id

/datum/unit_test/dq_p2_door/access_button_takes_a_swiped_id/run_gate()
	var/obj/p2_radio_listener/L = radio_listener()
	var/obj/machinery/access_button/airlock_interior/button = allocate(/obj/machinery/access_button/airlock_interior, tile(2, 2))
	p2_door_set_power(button, TRUE)
	button.req_access = list(ACCESS_ENGINE)
	var/mob/living/carbon/human/H = make_person(null, tile(3, 2))
	var/obj/item/card/id/card = give_item(H, /obj/item/card/id)
	card.access = list(ACCESS_ENGINE)
	click(H, button, card)
	TEST_ASSERT_EQUAL(LAZYLEN(L.heard), 1, "an ID swiped on it presses it")
	SSradio.remove_object(L, AIRLOCK_FREQ)

/datum/unit_test/dq_p2_door/airlock_sensor_cycles_by_hand_and_reports_pressure

/datum/unit_test/dq_p2_door/airlock_sensor_cycles_by_hand_and_reports_pressure/run_gate()
	var/obj/p2_radio_listener/L = radio_listener()
	var/obj/machinery/airlock_sensor/sensor = allocate(/obj/machinery/airlock_sensor/airlock_interior, tile(2, 2))
	p2_door_set_power(sensor, TRUE)
	sensor.master_tag = "p2_controller"
	sensor.id_tag = "p2_sensor"
	sensor.previousPressure = null // it read once when it was made, before it had its tag
	sensor.sample_pressure()
	var/mob/living/carbon/human/H = make_person(null, tile(3, 2))
	click(H, sensor, null)
	var/cycled = FALSE
	var/reported = FALSE
	for(var/list/signal in L.heard)
		if(signal["command"] == "cycle_interior" && signal["tag"] == "p2_controller")
			cycled = TRUE
		if(signal["tag"] == "p2_sensor" && !isnull(signal["pressure"]))
			reported = TRUE
	TEST_ASSERT(cycled, "a hand on it asks the controller to cycle")
	TEST_ASSERT(reported, "and it reports the pressure under its id tag")
	SSradio.remove_object(L, AIRLOCK_FREQ)

/datum/unit_test/dq_p2_door/access_button_is_set_with_a_multitool

/datum/unit_test/dq_p2_door/access_button_is_set_with_a_multitool/run_gate()
	var/obj/machinery/access_button/button = allocate(/obj/machinery/access_button/airlock_interior, tile(2, 2))
	p2_door_set_power(button, TRUE)
	var/mob/living/carbon/human/H = make_person(null, tile(3, 2))
	var/obj/item/tool = give_tool(H, /obj/item/multitool)
	p2_door_click(H, button, tool)
	p2_door_answer(H, "Tag")
	p2_door_answer(H, "p2_new_tag")
	settle()
	TEST_ASSERT_EQUAL(button.master_tag, "p2_new_tag", "the multitool sets the tag")
	p2_door_click(H, button, tool)
	p2_door_answer(H, "Command")
	p2_door_answer(H, "open")
	settle()
	TEST_ASSERT_EQUAL(button.command, "open", "and the command")
	p2_door_click(H, button, tool)
	p2_door_answer(H, "None")
	settle()
	TEST_ASSERT_EQUAL(button.command, "open", "None leaves it as it is")

// =====================================================================================================================
// BRIG DOOR TIMERS
// =====================================================================================================================

/// A timer, a brig windoor and a cell closet of one id, at (2, 2), (1, 2) and (4, 2); the door is open.
/datum/unit_test/dq_p2_door/proc/timer_setup(list/access)
	var/obj/machinery/door/window/brigdoor/D = allocate(/obj/machinery/door/window/brigdoor/p2_test, tile(1, 2))
	p2_door_set_power(D, TRUE)
	var/obj/machinery/door_timer/T = allocate(/obj/machinery/door_timer/p2_test, tile(2, 2))
	T.atom_fix() // it broke itself in its after-init pass, before its keyed doors had linked
	p2_door_set_power(T, TRUE)
	if(access)
		T.req_access = access
	return list(T, D)

/datum/unit_test/dq_p2_door/timer_closes_the_cell_then_lets_it_go

/datum/unit_test/dq_p2_door/timer_closes_the_cell_then_lets_it_go/run_gate()
	var/list/set_up = timer_setup()
	var/obj/machinery/door_timer/T = set_up[1]
	var/obj/machinery/door/window/brigdoor/D = set_up[2]
	D.open()
	test_time(2 SECONDS)
	TEST_ASSERT(!D.density, "the cell door is open")
	var/mob/living/carbon/human/H = make_person(list(ACCESS_BRIG), tile(3, 2))
	p2_door_ui(H, T, "time", list("time" = 6))
	p2_door_ui(H, T, "start")
	test_time(2 SECONDS)
	TEST_ASSERT(T.timing, "it is counting")
	TEST_ASSERT(D.density, "and the cell door is shut")
	test_time(10 SECONDS)
	TEST_ASSERT(!T.timing, "when the time is up it stops")
	TEST_ASSERT(!D.density, "and lets the door go")

/datum/unit_test/dq_p2_door/timer_stop_lets_it_go_early

/datum/unit_test/dq_p2_door/timer_stop_lets_it_go_early/run_gate()
	var/list/set_up = timer_setup()
	var/obj/machinery/door_timer/T = set_up[1]
	var/obj/machinery/door/window/brigdoor/D = set_up[2]
	D.open()
	test_time(2 SECONDS)
	var/mob/living/carbon/human/H = make_person(list(ACCESS_BRIG), tile(3, 2))
	p2_door_ui(H, T, "time", list("time" = 600))
	p2_door_ui(H, T, "start")
	test_time(2 SECONDS)
	TEST_ASSERT(D.density, "shut")
	p2_door_ui(H, T, "stop")
	test_time(2 SECONDS)
	TEST_ASSERT(!T.timing, "stopped")
	TEST_ASSERT(!D.density, "and the door is let go")

/datum/unit_test/dq_p2_door/timer_window_wants_access

/datum/unit_test/dq_p2_door/timer_window_wants_access/run_gate()
	var/list/set_up = timer_setup(list(ACCESS_BRIG))
	var/obj/machinery/door_timer/T = set_up[1]
	var/mob/living/carbon/human/stranger = make_person(null, tile(3, 2))
	p2_door_ui(stranger, T, "time", list("time" = 60))
	TEST_ASSERT_EQUAL(T.timer_duration, 0, "a stranger cannot set the time")
	var/mob/living/carbon/human/guard = make_person(list(ACCESS_BRIG), tile(3, 3))
	p2_door_ui(guard, T, "time", list("time" = 60))
	TEST_ASSERT_EQUAL(T.timer_duration, 600, "a guard can")
	p2_door_ui(guard, T, "preset", list("preset" = "short"))
	TEST_ASSERT_EQUAL(T.timer_duration, 600 + 600, "a preset is added to the time")

/datum/unit_test/dq_p2_door/timer_window_shows_what_it_counts

/datum/unit_test/dq_p2_door/timer_window_shows_what_it_counts/run_gate()
	var/list/set_up = timer_setup()
	var/obj/machinery/door_timer/T = set_up[1]
	var/list/data = T.ui_data(null)
	TEST_ASSERT(!data["timing"], "not counting")
	TEST_ASSERT_EQUAL(data["max_time_left"], MAX_TIMER, "with its longest time")

// =====================================================================================================================
// THE RECORDER
// =====================================================================================================================

/datum/unit_test/dq_p2_door/recorder_open_close

/datum/unit_test/dq_p2_door/recorder_open_close/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/engineer = make_person(list(ACCESS_ENGINE))
	var/mob/living/carbon/human/stranger = make_person(null, tile(3, 3))
	test_record(D)
	p2_door_click(engineer, D, null)
	settle()
	var/list/opening = test_recorded()
	TEST_ASSERT(!D.density, "the door opened")
	test_record(D)
	p2_door_click(engineer, D, null)
	settle()
	var/list/closing = test_recorded()
	TEST_ASSERT(D.density, "and closed")
	test_record(D)
	p2_door_click(stranger, D, null)
	settle()
	var/list/denied = test_recorded()
	TEST_ASSERT(D.density, "a stranger's attempt leaves it closed")
	// Whatever density deltas the record carries say the same thing the door did.
	var/last_open
	for(var/datum/test_event/E in opening)
		if(E.kind == TEST_EVENT_DELTA && E.key == "density")
			last_open = E.to_value
	if(!isnull(last_open))
		TEST_ASSERT(!last_open, "the opening record ends with density off")
	var/last_close
	for(var/datum/test_event/E in closing)
		if(E.kind == TEST_EVENT_DELTA && E.key == "density")
			last_close = E.to_value
	if(!isnull(last_close))
		TEST_ASSERT(last_close, "the closing record ends with density on")
	for(var/datum/test_event/E in denied)
		TEST_ASSERT(!(E.kind == TEST_EVENT_DELTA && E.key == "density"), "a refused attempt records no change of density")
		TEST_ASSERT(!(E.kind == TEST_EVENT_DELTA && E.key == "operating"), "a refused attempt records no change of operating")
	var/moved_open = 0
	for(var/datum/test_event/E in opening)
		if(E.kind == TEST_EVENT_DELTA && E.entity == D)
			moved_open++
	var/moved_denied = 0
	for(var/datum/test_event/E in denied)
		if(E.kind == TEST_EVENT_DELTA && E.entity == D)
			moved_denied++
	TEST_ASSERT(moved_denied <= moved_open, "a refusal records no more motion than an opening")
