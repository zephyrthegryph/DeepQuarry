// Behaviour-preservation tests for the light fixtures domain (phase 2): the fixtures (tube, bulb, small, spot, floor lamp, emergency and
// flickering types), the light items, the fixture frames, the light switch and its frame, the light replacer and the light painter. They pin what a
// player, an AI or a janitor can observe through public inputs (clicks, damage entry points, area power, time), so the same file passes before and
// after the domain moves from the interaction table to the engine forms.
//
// Rules the tests keep (as in dq_p2_apc_behaviour.dm):
//   - Input goes through input_submit() clicks (p2l_click), the area's own power_change(), the damage entry points and the kernel clock; never an
//     op key.
//   - State is read through the small adapter block below (the only place that names today's accessors) and plain vars (`on`, `status`,
//     `light_range`, `light_power`, `light_color`, `use_power`, `anchored`, `loc`).
//   - A tool is a zero-speed tool, and every input is followed by a settle (tool ops of the converted code carry waits the old code did not).
//   - Nothing here depends on message text, on an op key or on a click result being non-null.
//   - A test that reads a deadline that world.time owns on the legacy code (the emergency cell's discharge and recharge) runs live (`live = TRUE`).

// ---------------------------------------------------------------------------------------------------------------------
// Adapters: today's accessors, wrapped. After the conversion only these bodies change.
// ---------------------------------------------------------------------------------------------------------------------

/// The fixture's bulb state: LIGHT_OK, LIGHT_EMPTY, LIGHT_BURNED or LIGHT_BROKEN.
/proc/p2l_status(obj/machinery/light/L)
	return L.status

/// The bulb fitted in the fixture (a real item, made real if it was data), or null.
/proc/p2l_bulb(obj/machinery/light/L)
	return L.bulb()

/// Whether a bulb is fitted (real or data).
/proc/p2l_has_bulb(obj/machinery/light/L)
	return !!L.has_bulb()

/// The emergency cell of the fixture (made real if it was data), or null.
/proc/p2l_cell(obj/machinery/light/L)
	return L.emergency_cell()

/// Whether the fixture has an emergency cell, without making it real.
/proc/p2l_has_cell(obj/machinery/light/L)
	return !!L.has_cell()

/// The fixture is running on its emergency cell.
/proc/p2l_emergency(obj/machinery/light/L)
	return !!L.emergency_mode

/// A flicker run is in progress.
/proc/p2l_flickering(obj/machinery/light/L)
	return !!L.flickering

/// The night lighting is on at this fixture (the area's APC runs night shift and the fixture allows it).
/proc/p2l_nightshift(obj/machinery/light/L)
	return !!L.nightshift_enabled

/// The fixture is rigged to explode.
/proc/p2l_rigged(obj/machinery/light/L)
	return !!L.rigged

/// How many times the fixture was switched.
/proc/p2l_switchcount(obj/machinery/light/L)
	return L.switchcount

/// Sets how many times the fixture was switched (it decides the odds of the bulb burning out).
/proc/p2l_set_switchcount(obj/machinery/light/L, value)
	L.switchcount = value

/// The fixture's own brightness numbers (what a bulb gave it), as list(range, power, color).
/proc/p2l_numbers(obj/machinery/light/L)
	return list(L.brightness_range, L.brightness_power, L.brightness_color)

/// The fixture's night numbers, as list(range, power, color).
/proc/p2l_night_numbers(obj/machinery/light/L)
	return list(L.brightness_range_ns, L.brightness_power_ns, L.brightness_color_ns)

/// The fixture was told its area's lights changed power (the area's channel changed, or the light switch was used).
/proc/p2l_area_power_change(area/A)
	A.power_change()

/// The stage of the frame a screwdriver leaves when it opens an empty fixture (the legacy code lost the fixture argument and left a bare frame;
/// the converted frame is wired and remembers the fixture: intended_changes.md).
/proc/p2l_opened_frame_stage()
	return 2

/// The fixture's bulb state, with the light off at once when the bulb is not whole.
/proc/p2l_set_status(obj/machinery/light/L, value)
	L.set_bulb_status(value)

/// The frame's stage: 1 (empty frame), 2 (wired) or 3 (casing closed).
/proc/p2l_stage(obj/machinery/light_construct/C)
	return built(C, STAGE_LIGHT_FRAME_WIRED) ? 2 : 1

/// The emergency cell the frame holds, or null.
/proc/p2l_frame_cell(obj/machinery/light_construct/C)
	return C.cell

/// The light switch's frame stage: FRAME_UNFASTENED, FRAME_FASTENED or FRAME_WIRED.
/proc/p2l_switch_stage(obj/structure/construction/C)
	return C.frame_stage()

/// The light switch has no power (the NOPOWER state its own power change keeps).
/proc/p2l_switch_unpowered(obj/machinery/light_switch/S)
	return !!S.power_lost()

/// The area the switch works (its own area, or the one it is pointed at).
/proc/p2l_switch_area(obj/machinery/light_switch/S)
	return S.area()

/// Answers the question `actor` was asked with `value` (`cancel` closes it).
/proc/p2l_answer(mob/actor, value, cancel = FALSE)
	return test_answer(actor, value, cancel ? REQ_CANCELLED : REQ_ANSWERED)

/// A click as a player makes it: `held` in the active hand, the stance set, the click sent through the input inbox.
/proc/p2l_click(mob/living/carbon/human/H, atom/target, obj/item/held, stance = I_HELP, modifiers = "left=1")
	if(held && H.get_active_hand() != held)
		if(H.get_active_hand())
			H.drop_item()
		H.put_in_active_hand(held)
	else if(!held && H.get_active_hand())
		H.drop_item()
	H.set_use_stance(stance)
	H.next_click = 0
	var/datum/input_event/click/E = new(H, target, null, null, modifiers)
	input_submit(E)
	H.set_use_stance(I_HELP)
	return E.result

// ---------------------------------------------------------------------------------------------------------------------
// The base: the kernel on its injected clock around the test (unless it runs live), the area as it was after.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_lights
	abstract_type = /datum/unit_test/dq_p2_lights
	/// TRUE: real time and the live kernel (a deadline that world.time owns).
	var/live = FALSE
	var/area/p2l_area
	var/p2l_area_requires
	var/p2l_area_light
	var/p2l_area_switch
	var/p2l_area_equip
	var/list/p2l_apcs
	var/list/p2l_people

/datum/unit_test/dq_p2_lights/Run()
	if(!live)
		test_driver_begin()
	test_rng(11)
	p2l_area = get_area(run_loc_floor_bottom_left)
	p2l_area_requires = p2l_area.requires_power
	p2l_area_light = p2l_area.power_light
	p2l_area_switch = p2l_area.lightswitch
	p2l_area_equip = p2l_area.power_equip
	p2l_area.power_equip = TRUE
	p2l_area.requires_power = TRUE
	p2l_area.power_light = TRUE
	p2l_area.lightswitch = 1
	run_gate()
	for(var/mob/M as anything in p2l_people)
		while(SSrequests.open_for(M))
			test_answer(M, null, REQ_CANCELLED)
	for(var/obj/machinery/power/apc/A as anything in p2l_apcs)
		if(!QDELETED(A))
			qdel(A)
	own_turf_contents(run_loc_floor_bottom_left)
	own_turf_contents(run_loc_floor_top_right)
	p2l_area.requires_power = p2l_area_requires
	p2l_area.power_light = p2l_area_light
	p2l_area.lightswitch = p2l_area_switch
	p2l_area.power_equip = p2l_area_equip
	if(!live)
		test_driver_end()

/datum/unit_test/dq_p2_lights/proc/run_gate()
	return

/// A turf of the 5x5 room, `dx` and `dy` from its bottom-left corner.
/datum/unit_test/dq_p2_lights/proc/tile(dx, dy)
	return locate(run_loc_floor_bottom_left.x + dx, run_loc_floor_bottom_left.y + dy, run_loc_floor_bottom_left.z)

/// Time for a click to play out (a tool's wait, a timer, a flick): long on the injected clock, short when live.
/datum/unit_test/dq_p2_lights/proc/settle()
	if(live)
		sleep(1 SECONDS)
	else
		test_time(10 SECONDS)

/// A person with hands who cannot be knocked out by the test's passing time. Standing at (3, 2): next to the fixture at (2, 2), the switch at
/// (4, 2) and the frames around them.
/datum/unit_test/dq_p2_lights/proc/person(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || tile(3, 2))
	H.enable_godmode()
	LAZYADD(p2l_people, H)
	return H

/// A silicon AI, its core off in the corner.
/datum/unit_test/dq_p2_lights/proc/make_ai()
	return allocate(/mob/living/silicon/ai, tile(0, 0), null, null, null, TRUE)

/// A cyborg standing next to the fixtures.
/datum/unit_test/dq_p2_lights/proc/make_borg(turf/T)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T || tile(3, 2))
	R.enable_godmode()
	return R

/// Heat-proof gloves on the person (a lit tube is too hot to take out bare-handed).
/datum/unit_test/dq_p2_lights/proc/gloved(mob/living/carbon/human/H)
	var/obj/item/clothing/gloves/G = allocate(/obj/item/clothing/gloves, tile(0, 1))
	G.max_heat_protection_temperature = 1000
	H.equip_to_slot_or_del(G, SLOT_ID_GLOVES)
	return H

/// The actor clicks `target` with `held` in hand (nothing: an empty hand), in `stance`, and waits.
/datum/unit_test/dq_p2_lights/proc/click(mob/living/carbon/human/H, atom/target, obj/item/held, stance = I_HELP, modifiers = "left=1")
	p2l_click(H, target, held, stance, modifiers)
	settle()

/// A zero-speed tool of `path`.
/datum/unit_test/dq_p2_lights/proc/tool(path)
	return dq_fast_tool(path, tile(0, 1))

/// A fixture of `type` as a map places it (a bulb that happened to be broken at roundstart is mended: the placement roll is not what is under test).
/datum/unit_test/dq_p2_lights/proc/light(type = /obj/machinery/light, turf/T)
	var/obj/machinery/light/L = allocate(type, T || tile(2, 2))
	if(p2l_status(L) != LIGHT_OK)
		L.fix()
	settle()
	return L

/// A loose bulb or tube of `type`.
/datum/unit_test/dq_p2_lights/proc/bulb(type = /obj/item/light/tube, status = LIGHT_OK)
	var/obj/item/light/B = allocate(type, tile(3, 1))
	B.set_status(status)
	return B

/// An APC for the room's area, so the area has an APC to ask about night shift and emergency lighting. The area's channels are put back as
/// the test set them (the APC's own frame changes them).
/datum/unit_test/dq_p2_lights/proc/apc_for_area()
	var/obj/machinery/power/apc/A = allocate(/obj/machinery/power/apc, run_loc_floor_bottom_left)
	LAZYADD(p2l_apcs, A)
	settle()
	p2l_area.power_light = TRUE
	return A

/// The area loses (or regains) its light channel and tells the machines in it.
/datum/unit_test/dq_p2_lights/proc/set_area_power(powered)
	p2l_area.power_light = powered
	p2l_area_power_change(p2l_area)
	settle()

/// The area's light switch goes off (or on) as a light switch leaves it.
/datum/unit_test/dq_p2_lights/proc/set_area_switch(switched_on)
	p2l_area.lightswitch = switched_on
	p2l_area_power_change(p2l_area)
	settle()

// ---------------------------------------------------------------------------------------------------------------------
// What a fixture is when it is placed
// ---------------------------------------------------------------------------------------------------------------------

/// A tube fixture takes its numbers from its tube and draws power for them.
/datum/unit_test/dq_p2_lights/tube_fixture_starts_lit_with_the_tube_numbers

/datum/unit_test/dq_p2_lights/tube_fixture_starts_lit_with_the_tube_numbers/run_gate()
	var/obj/machinery/light/L = light()
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_OK, "a placed fixture has a working tube")
	TEST_ASSERT(L.on, "it is lit")
	TEST_ASSERT_EQUAL(L.light_range, 6, "tube range")
	TEST_ASSERT_EQUAL(L.light_power, 1, "tube power")
	TEST_ASSERT_EQUAL(L.light_color, LIGHT_COLOR_INCANDESCENT_TUBE, "tube colour")
	TEST_ASSERT_EQUAL(L.use_power, USE_POWER_ACTIVE, "it draws its active power")
	TEST_ASSERT_EQUAL(L.active_power_usage, 12, "two watts for each unit of range times power")

/// A small fixture takes a bulb: shorter range, less draw, the bulb colour.
/datum/unit_test/dq_p2_lights/small_fixture_starts_lit_with_the_bulb_numbers

/datum/unit_test/dq_p2_lights/small_fixture_starts_lit_with_the_bulb_numbers/run_gate()
	var/obj/machinery/light/small/L = light(/obj/machinery/light/small)
	TEST_ASSERT(L.on, "lit")
	TEST_ASSERT_EQUAL(L.light_range, 4, "bulb range")
	TEST_ASSERT_EQUAL(L.light_power, 1, "bulb power")
	TEST_ASSERT_EQUAL(L.light_color, LIGHT_COLOR_INCANDESCENT_BULB, "bulb colour")
	TEST_ASSERT_EQUAL(L.active_power_usage, 8, "draw follows range times power")

/// A spotlight takes a large tube and a floor lamp a large bulb.
/datum/unit_test/dq_p2_lights/spot_and_floor_lamp_take_their_large_lights

/datum/unit_test/dq_p2_lights/spot_and_floor_lamp_take_their_large_lights/run_gate()
	var/obj/machinery/light/spot/S = light(/obj/machinery/light/spot, tile(1, 3))
	TEST_ASSERT_EQUAL(S.light_range, 8, "large tube range")
	TEST_ASSERT_EQUAL(S.light_power, 2, "large tube power")
	TEST_ASSERT_EQUAL(S.active_power_usage, 32, "large tube draw")
	var/obj/machinery/light/flamp/F = light(/obj/machinery/light/flamp, tile(3, 3))
	TEST_ASSERT_EQUAL(F.light_range, 6, "large bulb range")
	TEST_ASSERT_EQUAL(F.light_power, 1, "large bulb power")
	TEST_ASSERT_EQUAL(F.active_power_usage, 12, "large bulb draw")

/// A placed fixture holds a charged emergency cell, unless it is a point-of-interest fixture.
/datum/unit_test/dq_p2_lights/placed_fixture_has_a_charged_emergency_cell

/datum/unit_test/dq_p2_lights/placed_fixture_has_a_charged_emergency_cell/run_gate()
	var/obj/machinery/light/L = light()
	TEST_ASSERT(p2l_has_cell(L), "a fixture has an emergency cell")
	var/obj/item/cell/emergency_light/C = p2l_cell(L)
	TEST_ASSERT(istype(C), "the cell is an emergency light cell")
	TEST_ASSERT_EQUAL(C.charge, C.maxcharge, "charged")
	var/obj/machinery/light/poi/P = light(/obj/machinery/light/poi, tile(3, 3))
	TEST_ASSERT(!p2l_has_cell(P), "a point-of-interest fixture has no cell")

/// A fixture placed in an area without light power starts dark; with a cell it is on emergency power.
/datum/unit_test/dq_p2_lights/fixture_placed_without_area_power_starts_dark

/datum/unit_test/dq_p2_lights/fixture_placed_without_area_power_starts_dark/run_gate()
	p2l_area.power_light = FALSE
	var/obj/machinery/light/poi/P = light(/obj/machinery/light/poi, tile(3, 3))
	TEST_ASSERT(!P.on, "no light power, no light")
	TEST_ASSERT_EQUAL(P.light_range, 0, "the light is out")
	TEST_ASSERT(!p2l_emergency(P), "nothing to run on")

/// The fixture types of the game keep their kind of bulb and their quirks.
/datum/unit_test/dq_p2_lights/fixture_types_keep_their_bulb_and_quirks

/datum/unit_test/dq_p2_lights/fixture_types_keep_their_bulb_and_quirks/run_gate()
	var/obj/machinery/light/small/emergency/E = allocate(/obj/machinery/light/small/emergency, tile(1, 3))
	TEST_ASSERT(ispath(E.light_type, /obj/item/light/bulb/red), "the emergency fixture takes a red bulb")
	TEST_ASSERT(!E.nightshift_allowed, "it ignores night shift")
	var/obj/machinery/light/no_nightshift/N = allocate(/obj/machinery/light/no_nightshift, tile(2, 3))
	TEST_ASSERT(!N.nightshift_allowed, "a no-nightshift fixture ignores night shift")
	var/obj/machinery/light/flicker/F = allocate(/obj/machinery/light/flicker, tile(3, 3))
	TEST_ASSERT(F.auto_flicker, "a flicker fixture flickers by itself on its cell")
	var/obj/machinery/light/small/fairylights/Y = allocate(/obj/machinery/light/small/fairylights, tile(4, 3))
	TEST_ASSERT(!Y.shows_alerts, "fairy lights show no alerts")
	var/obj/machinery/light/small/torch/T = allocate(/obj/machinery/light/small/torch, tile(4, 2))
	TEST_ASSERT(ispath(T.light_type, /obj/item/light/bulb/torch), "a torch takes a torch")

// ---------------------------------------------------------------------------------------------------------------------
// Area power and the light switch
// ---------------------------------------------------------------------------------------------------------------------

/// The area's light switch going off turns its lights off without starting their emergency power.
/datum/unit_test/dq_p2_lights/lightswitch_off_turns_the_light_off_without_emergency

/datum/unit_test/dq_p2_lights/lightswitch_off_turns_the_light_off_without_emergency/run_gate()
	var/obj/machinery/light/L = light()
	set_area_switch(0)
	TEST_ASSERT(!L.on, "switched off")
	TEST_ASSERT(!p2l_emergency(L), "a light that is switched off does not use its cell")
	TEST_ASSERT_EQUAL(L.light_range, 0, "it gives no light")
	set_area_switch(1)
	TEST_ASSERT(L.on, "switched on again (status [L.status], last [L.last_area_power], has_power [L.has_power()], switch [p2l_area.lightswitch], light [p2l_area.power_light], req [p2l_area.requires_power], sc [L.switchcount], subs [length(p2l_area.power_machines)] [L in p2l_area.power_machines], NOPOWER [L.power_lost()], flick [L.flickering])")
	TEST_ASSERT_EQUAL(L.light_range, 6, "its light is back")

/// Losing the light channel puts a fixture with a cell on its emergency power: dim, red, an eighth of the range.
/datum/unit_test/dq_p2_lights/area_power_loss_puts_a_fixture_on_emergency_power

/datum/unit_test/dq_p2_lights/area_power_loss_puts_a_fixture_on_emergency_power/run_gate()
	var/obj/machinery/light/L = light()
	set_area_power(FALSE)
	TEST_ASSERT(!L.on, "no longer on the grid")
	TEST_ASSERT(p2l_emergency(L), "on emergency power")
	TEST_ASSERT_EQUAL(L.light_range, 6 * 0.25, "a quarter of its range")
	TEST_ASSERT_EQUAL(L.light_color, L.bulb_emergency_colour, "emergency red")
	TEST_ASSERT_EQUAL(L.light_power, L.bulb_emergency_pow_mul, "the first level of emergency output")
	TEST_ASSERT_EQUAL(L.use_power, USE_POWER_IDLE, "it draws idle power")

/// A fixture with no cell goes dark when the area loses power.
/datum/unit_test/dq_p2_lights/area_power_loss_darkens_a_fixture_without_a_cell

/datum/unit_test/dq_p2_lights/area_power_loss_darkens_a_fixture_without_a_cell/run_gate()
	var/obj/machinery/light/poi/L = light(/obj/machinery/light/poi)
	TEST_ASSERT(L.on, "lit to begin with")
	set_area_power(FALSE)
	TEST_ASSERT(!L.on, "off")
	TEST_ASSERT(!p2l_emergency(L), "no cell, no emergency")
	TEST_ASSERT_EQUAL(L.light_range, 0, "dark")

/// A fixture that cannot have emergency lighting (switched off by an AI) goes dark too.
/datum/unit_test/dq_p2_lights/fixture_without_emergency_goes_dark_on_power_loss

/datum/unit_test/dq_p2_lights/fixture_without_emergency_goes_dark_on_power_loss/run_gate()
	var/obj/machinery/light/L = light()
	L.no_emergency = TRUE
	set_area_power(FALSE)
	TEST_ASSERT(!p2l_emergency(L), "no emergency lighting")
	TEST_ASSERT_EQUAL(L.light_range, 0, "dark")

/// Power returning ends the emergency and the light is back on the grid.
/datum/unit_test/dq_p2_lights/power_returning_ends_the_emergency

/datum/unit_test/dq_p2_lights/power_returning_ends_the_emergency/run_gate()
	var/obj/machinery/light/L = light()
	set_area_power(FALSE)
	TEST_ASSERT(p2l_emergency(L), "emergency first")
	set_area_power(TRUE)
	TEST_ASSERT(L.on, "back on")
	TEST_ASSERT(!p2l_emergency(L), "the emergency is over")
	TEST_ASSERT_EQUAL(L.light_range, 6, "its normal range")
	TEST_ASSERT_EQUAL(L.use_power, USE_POWER_ACTIVE, "it draws active power again")

/// The light switch off, then power lost: the fixture stays dark (a switched-off light never uses its cell).
/datum/unit_test/dq_p2_lights/switched_off_fixture_stays_dark_when_power_is_lost

/datum/unit_test/dq_p2_lights/switched_off_fixture_stays_dark_when_power_is_lost/run_gate()
	var/obj/machinery/light/L = light()
	set_area_switch(0)
	set_area_power(FALSE)
	TEST_ASSERT(!L.on, "off")
	TEST_ASSERT(!p2l_emergency(L), "a light that is switched off stays dark on a power loss")
	TEST_ASSERT_EQUAL(L.light_range, 0, "dark")

/// A broken, burned or empty fixture stays dark whatever the area does.
/datum/unit_test/dq_p2_lights/power_changes_do_not_light_a_dead_fixture

/datum/unit_test/dq_p2_lights/power_changes_do_not_light_a_dead_fixture/run_gate()
	var/obj/machinery/light/L = light(/obj/machinery/light, tile(1, 3))
	var/obj/machinery/light/M = light(/obj/machinery/light, tile(2, 3))
	var/obj/machinery/light/N = light(/obj/machinery/light, tile(3, 3))
	L.broken()
	p2l_set_status(M, LIGHT_BURNED)
	p2l_make_empty(N)
	set_area_switch(0)
	set_area_switch(1)
	TEST_ASSERT(!L.on, "a broken fixture stays dark")
	TEST_ASSERT(!M.on, "a burned fixture stays dark")
	TEST_ASSERT(!N.on, "an empty fixture stays dark")
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_BROKEN, "still broken")

/// An area that needs no power keeps its lights on whatever its light channel says.
/datum/unit_test/dq_p2_lights/area_without_a_power_requirement_keeps_the_lights_on

/datum/unit_test/dq_p2_lights/area_without_a_power_requirement_keeps_the_lights_on/run_gate()
	var/obj/machinery/light/L = light()
	p2l_area.requires_power = FALSE
	set_area_power(FALSE)
	TEST_ASSERT(L.on, "lit: the area does not need power")
	TEST_ASSERT(!p2l_emergency(L), "and not on the cell")

/// A fixture that is on is the area's load on the light channel; a fixture that is off is idle.
/datum/unit_test/dq_p2_lights/fixture_power_use_follows_its_state

/datum/unit_test/dq_p2_lights/fixture_power_use_follows_its_state/run_gate()
	var/before = dq_grid_demand(p2l_area, LIGHT)
	var/obj/machinery/light/L = light()
	TEST_ASSERT_EQUAL(dq_grid_demand(p2l_area, LIGHT) - before, 12, "an active tube is twelve watts of the area's light channel")
	set_area_switch(0)
	TEST_ASSERT_EQUAL(dq_grid_demand(p2l_area, LIGHT) - before, 2, "a switched-off fixture draws its idle two watts")
	set_area_switch(1)
	TEST_ASSERT_EQUAL(dq_grid_demand(p2l_area, LIGHT) - before, 12, "back to active")
	qdel(L)
	settle()
	TEST_ASSERT_EQUAL(dq_grid_demand(p2l_area, LIGHT) - before, 0, "a deleted fixture draws nothing")

// ---------------------------------------------------------------------------------------------------------------------
// The emergency cell (live: the discharge and the recharge run on world.time)
// ---------------------------------------------------------------------------------------------------------------------

/// On emergency power the cell drains at 0.1 charge per second, settled in batches: reading it brings it up to now.
/datum/unit_test/dq_p2_lights/emergency_cell_drains_while_the_fixture_runs_on_it
	live = TRUE

/datum/unit_test/dq_p2_lights/emergency_cell_drains_while_the_fixture_runs_on_it/run_gate()
	var/obj/machinery/light/L = light()
	var/obj/item/cell/C = p2l_cell(L)
	var/start = C.charge
	set_area_power(FALSE)
	sleep(11 SECONDS)
	L.settle_emergency_discharge()
	var/drained = start - C.charge
	TEST_ASSERT(drained > 0.8 && drained < 1.4, "ten seconds on the cell cost about one charge, not [drained]")

/// A fixture on emergency power from a cell that is too strong for the ballast burns out at once.
/datum/unit_test/dq_p2_lights/an_oversized_cell_burns_the_fixture_out_on_emergency_power

/datum/unit_test/dq_p2_lights/an_oversized_cell_burns_the_fixture_out_on_emergency_power/run_gate()
	var/obj/machinery/light/L = light()
	var/obj/item/cell/C = p2l_cell(L)
	C.maxcharge = 2000
	C.charge = 2000
	set_area_power(FALSE)
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_BURNED, "the tube burned out")

/// The cell recharges in time once the grid is back (live).
/datum/unit_test/dq_p2_lights/emergency_cell_recharges_when_power_returns
	live = TRUE

/datum/unit_test/dq_p2_lights/emergency_cell_recharges_when_power_returns/run_gate()
	var/obj/machinery/light/L = light()
	var/obj/item/cell/C = p2l_cell(L)
	C.charge = C.maxcharge - 0.6 // one recharge step of 0.4 every two seconds: two steps
	set_area_power(FALSE)
	set_area_power(TRUE)
	TEST_ASSERT(C.charge < C.maxcharge, "not charged at once")
	sleep(8 SECONDS)
	TEST_ASSERT_EQUAL(C.charge, C.maxcharge, "charged to full after a few seconds on the grid")

/// An AI toggles a fixture's emergency lighting; a fixture with it off goes dark on a power loss.
/datum/unit_test/dq_p2_lights/ai_toggles_a_fixtures_emergency_lighting

/datum/unit_test/dq_p2_lights/ai_toggles_a_fixtures_emergency_lighting/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/silicon/ai/AI = make_ai()
	TEST_ASSERT(!L.no_emergency, "emergency lighting to start with")
	p2l_click(AI, L, null)
	settle()
	TEST_ASSERT(L.no_emergency, "the AI switched it off")
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_OK, "and did not take the bulb out: an AI has no hands")
	p2l_click(AI, L, null)
	settle()
	TEST_ASSERT(!L.no_emergency, "and on again")

/// The area's APC can switch emergency lighting off for the whole area.
/datum/unit_test/dq_p2_lights/apc_emergency_switch_stops_emergency_lighting

/datum/unit_test/dq_p2_lights/apc_emergency_switch_stops_emergency_lighting/run_gate()
	var/obj/machinery/power/apc/A = apc_for_area()
	var/obj/machinery/light/L = light()
	A.set_emergency_lights(TRUE)
	settle()
	set_area_power(FALSE)
	TEST_ASSERT(!p2l_emergency(L), "no emergency lighting with the APC's switch on")
	TEST_ASSERT_EQUAL(L.light_range, 0, "dark")
	set_area_power(TRUE)
	A.set_emergency_lights(FALSE)
	settle()
	set_area_power(FALSE)
	TEST_ASSERT(p2l_emergency(L), "with the switch off the fixture lights its emergency light")

// ---------------------------------------------------------------------------------------------------------------------
// Night shift
// ---------------------------------------------------------------------------------------------------------------------

/// Night shift always on in the area: a fixture dims to its bulb's night numbers.
/datum/unit_test/dq_p2_lights/nightshift_changes_a_fixture_to_its_night_numbers

/datum/unit_test/dq_p2_lights/nightshift_changes_a_fixture_to_its_night_numbers/run_gate()
	var/obj/machinery/power/apc/A = apc_for_area()
	var/obj/machinery/light/L = light()
	A.set_nightshift_setting(NIGHTSHIFT_ALWAYS)
	settle()
	TEST_ASSERT(p2l_nightshift(L), "night lighting on")
	TEST_ASSERT_EQUAL(L.light_range, 6, "the tube's night range")
	TEST_ASSERT_EQUAL(L.light_power, 0.45, "the tube's night power")
	TEST_ASSERT_EQUAL(L.light_color, LIGHT_COLOR_NIGHTSHIFT, "the night colour")
	A.set_nightshift_setting(NIGHTSHIFT_NEVER)
	settle()
	TEST_ASSERT(!p2l_nightshift(L), "night lighting off")
	TEST_ASSERT_EQUAL(L.light_power, 1, "back to the day power")
	TEST_ASSERT_EQUAL(L.light_color, LIGHT_COLOR_INCANDESCENT_TUBE, "back to the day colour")

/// A tube that was tuned to another night range gives its fixture that range at night.
/datum/unit_test/dq_p2_lights/nightshift_uses_the_tube_night_range

/datum/unit_test/dq_p2_lights/nightshift_uses_the_tube_night_range/run_gate()
	var/obj/machinery/power/apc/A = apc_for_area()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = gloved(person())
	var/obj/item/light/B = p2l_bulb(L)
	B.nightshift_range = 3
	click(H, L, null) // the tube comes out and goes back in, so the fixture takes its numbers again
	click(H, L, B)
	TEST_ASSERT_EQUAL(L.light_range, 6, "the day range by day")
	A.set_nightshift_setting(NIGHTSHIFT_ALWAYS)
	settle()
	TEST_ASSERT_EQUAL(L.light_range, 3, "the tube's night range by night")
	A.set_nightshift_setting(NIGHTSHIFT_NEVER)
	settle()
	TEST_ASSERT_EQUAL(L.light_range, 6, "and the day range again")

/// A fixture that does not allow night shift keeps its day numbers.
/datum/unit_test/dq_p2_lights/nightshift_leaves_a_no_nightshift_fixture_alone

/datum/unit_test/dq_p2_lights/nightshift_leaves_a_no_nightshift_fixture_alone/run_gate()
	var/obj/machinery/power/apc/A = apc_for_area()
	var/obj/machinery/light/no_nightshift/L = light(/obj/machinery/light/no_nightshift)
	A.set_nightshift_setting(NIGHTSHIFT_ALWAYS)
	settle()
	TEST_ASSERT(!p2l_nightshift(L), "it does not take night lighting")
	TEST_ASSERT_EQUAL(L.light_power, 1, "day power")

/// A fixture placed while night shift is on starts in night lighting; the night numbers are the bulb's.
/datum/unit_test/dq_p2_lights/fixture_placed_at_night_starts_in_night_lighting

/datum/unit_test/dq_p2_lights/fixture_placed_at_night_starts_in_night_lighting/run_gate()
	var/obj/machinery/power/apc/A = apc_for_area()
	A.set_nightshift_setting(NIGHTSHIFT_ALWAYS)
	settle()
	var/obj/machinery/light/small/L = light(/obj/machinery/light/small)
	TEST_ASSERT(p2l_nightshift(L), "night lighting on from the start")
	TEST_ASSERT_EQUAL(L.light_power, 0.45, "the small bulb's night power")
	TEST_ASSERT_EQUAL(L.light_range, 4, "the small bulb's night range")

// ---------------------------------------------------------------------------------------------------------------------
// Bulbs in and out of a fixture
// ---------------------------------------------------------------------------------------------------------------------

/// An empty fixture (the bulb taken out, as a hand takes it).
/proc/p2l_make_empty(obj/machinery/light/L)
	L.remove_bulb()

/// A matching tube clicked on an empty fixture goes in: the fixture takes its state and its numbers, and lights if it has power.
/datum/unit_test/dq_p2_lights/matching_tube_goes_into_an_empty_fixture

/datum/unit_test/dq_p2_lights/matching_tube_goes_into_an_empty_fixture/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	p2l_make_empty(L)
	settle()
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_EMPTY, "the fixture is empty")
	TEST_ASSERT(!L.on, "an empty fixture is dark")
	var/obj/item/light/tube/B = bulb()
	click(H, L, B)
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_OK, "the tube went in")
	TEST_ASSERT(p2l_bulb(L) == B && B.loc == L, "it is the tube in the fixture")
	TEST_ASSERT(L.on, "and the fixture is lit")
	TEST_ASSERT_EQUAL(L.light_range, 6, "with the tube range")

/// A light of the wrong kind is not taken.
/datum/unit_test/dq_p2_lights/wrong_kind_of_light_is_refused

/datum/unit_test/dq_p2_lights/wrong_kind_of_light_is_refused/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	p2l_make_empty(L)
	settle()
	var/obj/item/light/B = bulb(/obj/item/light/bulb)
	click(H, L, B)
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_EMPTY, "a bulb does not fit a tube fixture")
	TEST_ASSERT(B.loc != L, "the bulb is not in it")

/// A fixture with a bulb already in it does not take another.
/datum/unit_test/dq_p2_lights/occupied_fixture_refuses_a_second_tube

/datum/unit_test/dq_p2_lights/occupied_fixture_refuses_a_second_tube/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	var/obj/item/light/tube/B = bulb()
	var/obj/item/light/first = p2l_bulb(L)
	click(H, L, B)
	TEST_ASSERT(p2l_bulb(L) == first, "the first tube is still the one in it")
	TEST_ASSERT(B.loc != L, "the second is not")

/// A broken or burned tube goes in as it is: the fixture takes its state.
/datum/unit_test/dq_p2_lights/broken_and_burned_tubes_go_in_as_they_are

/datum/unit_test/dq_p2_lights/broken_and_burned_tubes_go_in_as_they_are/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	p2l_make_empty(L)
	settle()
	click(H, L, bulb(/obj/item/light/tube, LIGHT_BROKEN))
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_BROKEN, "a broken tube makes a broken fixture")
	p2l_make_empty(L)
	settle()
	click(H, L, bulb(/obj/item/light/tube, LIGHT_BURNED))
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_BURNED, "a burned tube makes a burned fixture")

/// With the area switch off a new tube does not light.
/datum/unit_test/dq_p2_lights/tube_inserted_while_the_switch_is_off_stays_dark

/datum/unit_test/dq_p2_lights/tube_inserted_while_the_switch_is_off_stays_dark/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	p2l_make_empty(L)
	set_area_switch(0)
	click(H, L, bulb())
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_OK, "the tube is in")
	TEST_ASSERT(!L.on, "the area switch is off: it does not light")
	set_area_switch(1)
	TEST_ASSERT(L.on, "switched on, it lights")

/// A rigged tube lights and the fixture blows up.
/datum/unit_test/dq_p2_lights/rigged_tube_explodes_the_fixture

/datum/unit_test/dq_p2_lights/rigged_tube_explodes_the_fixture/run_gate()
	var/obj/machinery/light/L = light(/obj/machinery/light, tile(4, 4))
	var/mob/living/carbon/human/H = person(tile(3, 4))
	p2l_make_empty(L)
	settle()
	var/obj/item/light/tube/B = bulb()
	B.rigged = 1
	click(H, L, B)
	TEST_ASSERT(QDELETED(L), "the fixture exploded")

/// An empty hand takes the tube out: the fixture is empty, dark and its switch count starts over.
/datum/unit_test/dq_p2_lights/hand_takes_the_tube_out

/datum/unit_test/dq_p2_lights/hand_takes_the_tube_out/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	set_area_switch(0)
	p2l_set_switchcount(L, 7)
	click(H, L, null)
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_EMPTY, "the fixture is empty")
	TEST_ASSERT(istype(H.get_active_hand(), /obj/item/light/tube), "the tube is in the hand")
	TEST_ASSERT(!L.on, "dark")
	TEST_ASSERT_EQUAL(p2l_switchcount(L), 0, "the count starts over")
	TEST_ASSERT(!p2l_has_bulb(L), "no bulb in it")

/// A lit tube is too hot for a bare hand; gloves that take the heat (or an unlit tube) let it come out.
/datum/unit_test/dq_p2_lights/lit_tube_needs_heat_proof_gloves

/datum/unit_test/dq_p2_lights/lit_tube_needs_heat_proof_gloves/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	TEST_ASSERT(L.on, "lit")
	click(H, L, null)
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_OK, "a bare hand leaves a lit tube in")
	TEST_ASSERT_NULL(H.get_active_hand(), "and holds nothing")
	var/obj/item/clothing/gloves/G = allocate(/obj/item/clothing/gloves, tile(0, 1))
	G.max_heat_protection_temperature = 1000
	H.equip_to_slot_or_del(G, SLOT_ID_GLOVES)
	click(H, L, null)
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_EMPTY, "gloves that take the heat let it come out")
	TEST_ASSERT(istype(H.get_active_hand(), /obj/item/light/tube), "into the hand")

/// A broken tube comes out broken.
/datum/unit_test/dq_p2_lights/broken_tube_comes_out_broken

/datum/unit_test/dq_p2_lights/broken_tube_comes_out_broken/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	L.broken()
	settle()
	click(H, L, null)
	var/obj/item/light/B = H.get_active_hand()
	TEST_ASSERT(istype(B), "a tube in the hand")
	TEST_ASSERT_EQUAL(B.status, LIGHT_BROKEN, "it is broken")
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_EMPTY, "the fixture is empty")

/// An empty fixture gives nothing to a hand.
/datum/unit_test/dq_p2_lights/hand_takes_nothing_from_an_empty_fixture

/datum/unit_test/dq_p2_lights/hand_takes_nothing_from_an_empty_fixture/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	p2l_make_empty(L)
	settle()
	click(H, L, null)
	TEST_ASSERT_NULL(H.get_active_hand(), "nothing to take")
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_EMPTY, "still empty")

/// A tube taken out and put back in is the same tube and the fixture works as before.
/datum/unit_test/dq_p2_lights/tube_taken_out_and_put_back_works_again

/datum/unit_test/dq_p2_lights/tube_taken_out_and_put_back_works_again/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = gloved(person())
	click(H, L, null)
	var/obj/item/light/B = H.get_active_hand()
	click(H, L, B)
	TEST_ASSERT(p2l_bulb(L) == B, "the same tube is back in")
	TEST_ASSERT(L.on, "lit")
	TEST_ASSERT_EQUAL(L.light_range, 6, "with its range")

/// A tube taken out of one fixture keeps its custom numbers into another.
/datum/unit_test/dq_p2_lights/a_tuned_tube_keeps_its_numbers_between_fixtures

/datum/unit_test/dq_p2_lights/a_tuned_tube_keeps_its_numbers_between_fixtures/run_gate()
	var/obj/machinery/light/L = light(/obj/machinery/light, tile(2, 2))
	var/obj/machinery/light/M = light(/obj/machinery/light, tile(4, 2))
	var/mob/living/carbon/human/H = gloved(person())
	var/obj/item/light/tube/B = p2l_bulb(L)
	B.brightness_range = 3
	B.brightness_color = "#123456"
	click(H, L, null)
	p2l_make_empty(M)
	settle()
	click(H, M, B)
	TEST_ASSERT_EQUAL(M.light_range, 3, "the tuned range (status [p2l_status(M)], on [M.on], bulb [p2l_has_bulb(M)], hand [H.get_active_hand()])")
	TEST_ASSERT_EQUAL(M.light_color, "#123456", "the tuned colour")

// ---------------------------------------------------------------------------------------------------------------------
// Hitting, opening and tuning a fixture
// ---------------------------------------------------------------------------------------------------------------------

/// A heavy item smashes a fixture.
/datum/unit_test/dq_p2_lights/heavy_item_smashes_the_fixture

/datum/unit_test/dq_p2_lights/heavy_item_smashes_the_fixture/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	var/obj/item/I = allocate(/obj/item, tile(0, 1))
	I.force = 30
	I.flags |= NOCONDUCT
	click(H, L, I, I_HURT)
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_BROKEN, "smashed")
	TEST_ASSERT(!L.on, "dark")
	TEST_ASSERT_EQUAL(L.light_range, 0, "no light")

/// A feather does not (a one in a hundred roll, seeded).
/datum/unit_test/dq_p2_lights/weak_item_does_not_smash_the_fixture

/datum/unit_test/dq_p2_lights/weak_item_does_not_smash_the_fixture/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	var/obj/item/I = allocate(/obj/item, tile(0, 1))
	I.force = 0
	I.flags |= NOCONDUCT
	click(H, L, I, I_HURT)
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_OK, "not smashed")
	TEST_ASSERT(L.on, "still lit")

/// A weapon pushed into an empty socket changes nothing.
/datum/unit_test/dq_p2_lights/item_pushed_into_an_empty_socket_changes_nothing

/datum/unit_test/dq_p2_lights/item_pushed_into_an_empty_socket_changes_nothing/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	p2l_make_empty(L)
	settle()
	var/obj/item/I = allocate(/obj/item, tile(0, 1))
	I.force = 30
	click(H, L, I, I_HURT)
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_EMPTY, "still empty")
	TEST_ASSERT(I.loc != L, "the item stays out")

/// A screwdriver opens an empty fixture into a frame, and the fixture is gone.
/datum/unit_test/dq_p2_lights/screwdriver_opens_an_empty_fixture_into_a_frame

/datum/unit_test/dq_p2_lights/screwdriver_opens_an_empty_fixture_into_a_frame/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	p2l_make_empty(L)
	settle()
	var/turf/T = L.loc
	click(H, L, tool(/obj/item/tool/screwdriver))
	TEST_ASSERT(QDELETED(L), "the fixture is gone")
	var/obj/machinery/light_construct/C = locate(/obj/machinery/light_construct) in T
	TEST_ASSERT(istype(C), "a frame stands where it was")
	TEST_ASSERT_EQUAL(p2l_stage(C), p2l_opened_frame_stage(), "the frame's stage")
	TEST_ASSERT(C.fixture_type == /obj/machinery/light, "it builds a fixture of the default kind")
	qdel(C)

/// A screwdriver on a fixture that still has its tube does nothing.
/datum/unit_test/dq_p2_lights/screwdriver_leaves_a_fixture_with_a_tube_alone

/datum/unit_test/dq_p2_lights/screwdriver_leaves_a_fixture_with_a_tube_alone/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	click(H, L, tool(/obj/item/tool/screwdriver))
	TEST_ASSERT(!QDELETED(L), "still a fixture")
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_OK, "with its tube")

/// Opening a small fixture gives the small frame.
/datum/unit_test/dq_p2_lights/screwdriver_opens_a_small_fixture_into_a_small_frame

/datum/unit_test/dq_p2_lights/screwdriver_opens_a_small_fixture_into_a_small_frame/run_gate()
	var/obj/machinery/light/small/L = light(/obj/machinery/light/small)
	var/mob/living/carbon/human/H = person()
	p2l_make_empty(L)
	settle()
	var/turf/T = L.loc
	click(H, L, tool(/obj/item/tool/screwdriver))
	var/obj/machinery/light_construct/small/C = locate(/obj/machinery/light_construct/small) in T
	TEST_ASSERT(istype(C), "a small frame")
	TEST_ASSERT(C.fixture_type == /obj/machinery/light/small, "that builds a small fixture")
	qdel(C)

/// A multitool on a fixture asks what to change about its tube and retunes it.
/datum/unit_test/dq_p2_lights/multitool_retunes_the_tube_in_a_fixture

/datum/unit_test/dq_p2_lights/multitool_retunes_the_tube_in_a_fixture/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	p2l_click(H, L, tool(/obj/item/multitool))
	p2l_answer(H, "Normal Range")
	p2l_answer(H, 3)
	settle()
	var/obj/item/light/B = p2l_bulb(L)
	TEST_ASSERT_EQUAL(B.brightness_range, 3, "the tube range changed")
	TEST_ASSERT_EQUAL(L.light_range, 3, "and the fixture follows")

/// A multitool on a fixture with no working tube does nothing.
/datum/unit_test/dq_p2_lights/multitool_does_nothing_to_a_broken_fixture

/datum/unit_test/dq_p2_lights/multitool_does_nothing_to_a_broken_fixture/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	L.broken()
	settle()
	var/obj/item/light/B = p2l_bulb(L)
	var/before = B.brightness_range
	p2l_click(H, L, tool(/obj/item/multitool))
	p2l_answer(H, "Normal Range")
	p2l_answer(H, 3)
	settle()
	TEST_ASSERT_EQUAL(B.brightness_range, before, "nothing was asked, nothing changed")

/// A multitool on a loose tube retunes its night power.
/datum/unit_test/dq_p2_lights/multitool_retunes_a_loose_tube

/datum/unit_test/dq_p2_lights/multitool_retunes_a_loose_tube/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/light/tube/B = bulb()
	p2l_click(H, B, tool(/obj/item/multitool))
	p2l_answer(H, "Nightshift Brightness")
	p2l_answer(H, 0.2)
	settle()
	TEST_ASSERT_EQUAL(B.nightshift_power, 0.2, "the night power changed")

/// A multitool recolours a tube; in a fixture the fixture takes the colour.
/datum/unit_test/dq_p2_lights/multitool_recolours_a_tube

/datum/unit_test/dq_p2_lights/multitool_recolours_a_tube/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	p2l_click(H, L, tool(/obj/item/multitool))
	p2l_answer(H, "Normal Color")
	p2l_answer(H, "#00ff00")
	settle()
	var/obj/item/light/B = p2l_bulb(L)
	TEST_ASSERT_EQUAL(B.brightness_color, "#00ff00", "the tube colour")
	TEST_ASSERT_EQUAL(L.light_color, "#00ff00", "the fixture light")

// ---------------------------------------------------------------------------------------------------------------------
// Flickering
// ---------------------------------------------------------------------------------------------------------------------

/// Flicks still to go in a flicker run.
/proc/p2l_flicks_left(obj/machinery/light/L)
	return L.flicks_left

/// A flicker run starts at once, runs its flicks and leaves the fixture lit as before.
/datum/unit_test/dq_p2_lights/flicker_runs_then_restores_the_light

/datum/unit_test/dq_p2_lights/flicker_runs_then_restores_the_light/run_gate()
	var/obj/machinery/light/L = light()
	var/list/before = p2l_numbers(L)
	L.flicker(3)
	TEST_ASSERT(p2l_flickering(L), "flickering")
	settle()
	TEST_ASSERT(!p2l_flickering(L), "the run is over")
	TEST_ASSERT(L.on, "lit again")
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_OK, "the tube is whole")
	TEST_ASSERT_EQUAL(L.light_range, 6, "its range is back")
	var/list/after = p2l_numbers(L)
	TEST_ASSERT_EQUAL(after[3], before[3], "its colour is back")

/// A flicker with a colour shows that colour while it runs and gives the old one back.
/datum/unit_test/dq_p2_lights/flicker_colour_shows_then_restores

/datum/unit_test/dq_p2_lights/flicker_colour_shows_then_restores/run_gate()
	var/obj/machinery/light/L = light()
	L.flicker(5, "#00ff00")
	var/list/during = p2l_numbers(L)
	TEST_ASSERT_EQUAL(during[3], "#00ff00", "the flicker colour is on the fixture")
	settle()
	var/list/after = p2l_numbers(L)
	TEST_ASSERT_EQUAL(after[3], LIGHT_COLOR_INCANDESCENT_TUBE, "the tube colour is back")
	TEST_ASSERT_EQUAL(L.light_color, LIGHT_COLOR_INCANDESCENT_TUBE, "and the light shows it")

/// A fixture that is not lit does not flicker.
/datum/unit_test/dq_p2_lights/flicker_needs_a_lit_fixture

/datum/unit_test/dq_p2_lights/flicker_needs_a_lit_fixture/run_gate()
	var/obj/machinery/light/L = light()
	set_area_switch(0)
	L.flicker(3)
	TEST_ASSERT(!p2l_flickering(L), "dark: nothing to flicker")

/// A broken fixture does not flicker.
/datum/unit_test/dq_p2_lights/flicker_needs_a_whole_tube

/datum/unit_test/dq_p2_lights/flicker_needs_a_whole_tube/run_gate()
	var/obj/machinery/light/L = light()
	L.broken()
	settle()
	L.flicker(3)
	TEST_ASSERT(!p2l_flickering(L), "broken: nothing to flicker")

/// A flicker that is running is not restarted.
/datum/unit_test/dq_p2_lights/flicker_while_flickering_is_ignored

/datum/unit_test/dq_p2_lights/flicker_while_flickering_is_ignored/run_gate()
	var/obj/machinery/light/L = light()
	L.flicker(3)
	var/left = p2l_flicks_left(L)
	L.flicker(40)
	TEST_ASSERT(p2l_flicks_left(L) <= left, "the second call changed nothing")

/// A tube that breaks while flickering ends the run broken.
/datum/unit_test/dq_p2_lights/flicker_stops_when_the_tube_breaks

/datum/unit_test/dq_p2_lights/flicker_stops_when_the_tube_breaks/run_gate()
	var/obj/machinery/light/L = light()
	L.flicker(15)
	L.broken()
	settle()
	TEST_ASSERT(!p2l_flickering(L), "the run stopped")
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_BROKEN, "broken")
	TEST_ASSERT(!L.on, "dark")

/// An AI alt-clicking a fixture makes it flicker.
/datum/unit_test/dq_p2_lights/ai_alt_click_flickers_a_fixture

/datum/unit_test/dq_p2_lights/ai_alt_click_flickers_a_fixture/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/silicon/ai/AI = make_ai()
	p2l_click(AI, L, null, I_HELP, "left=1;alt=1")
	TEST_ASSERT(p2l_flickering(L), "flickering after the AI's alt-click")
	settle()
	TEST_ASSERT(!p2l_flickering(L), "and it ends")

// ---------------------------------------------------------------------------------------------------------------------
// Breaking, mending and burning out
// ---------------------------------------------------------------------------------------------------------------------

/// A broken fixture is dark and its tube is marked broken.
/datum/unit_test/dq_p2_lights/broken_fixture_goes_dark_with_a_broken_tube

/datum/unit_test/dq_p2_lights/broken_fixture_goes_dark_with_a_broken_tube/run_gate()
	var/obj/machinery/light/L = light()
	var/obj/item/light/B = p2l_bulb(L) // a real tube in it before it breaks
	L.broken()
	settle()
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_BROKEN, "broken")
	TEST_ASSERT(!L.on, "dark")
	TEST_ASSERT_EQUAL(L.light_range, 0, "no light")
	TEST_ASSERT_EQUAL(L.use_power, USE_POWER_IDLE, "idle power")
	TEST_ASSERT_EQUAL(B.status, LIGHT_BROKEN, "the tube in it is broken")

/// An empty fixture cannot be broken; a burned one can.
/datum/unit_test/dq_p2_lights/empty_fixture_stays_empty_and_burned_one_breaks

/datum/unit_test/dq_p2_lights/empty_fixture_stays_empty_and_burned_one_breaks/run_gate()
	var/obj/machinery/light/L = light()
	p2l_make_empty(L)
	settle()
	L.broken()
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_EMPTY, "still empty")
	var/obj/machinery/light/M = light(/obj/machinery/light, tile(3, 3))
	p2l_set_status(M, LIGHT_BURNED)
	M.broken()
	TEST_ASSERT_EQUAL(p2l_status(M), LIGHT_BROKEN, "a burned tube breaks")

/// Fairy lights cannot be broken.
/datum/unit_test/dq_p2_lights/fairy_lights_do_not_break

/datum/unit_test/dq_p2_lights/fairy_lights_do_not_break/run_gate()
	var/obj/machinery/light/small/fairylights/Y = light(/obj/machinery/light/small/fairylights)
	Y.broken()
	TEST_ASSERT_EQUAL(p2l_status(Y), LIGHT_OK, "unbroken")

/// Mending a broken fixture lights it with a whole tube.
/datum/unit_test/dq_p2_lights/fix_mends_a_broken_fixture

/datum/unit_test/dq_p2_lights/fix_mends_a_broken_fixture/run_gate()
	var/obj/machinery/light/L = light()
	L.broken()
	settle()
	L.fix()
	settle()
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_OK, "mended")
	TEST_ASSERT(L.on, "lit")
	TEST_ASSERT_EQUAL(L.light_range, 6, "its range")
	var/obj/item/light/B = p2l_bulb(L)
	TEST_ASSERT_EQUAL(B.status, LIGHT_OK, "the tube is whole")

/// Damage past half the fixture's integrity breaks it.
/datum/unit_test/dq_p2_lights/damage_past_half_breaks_the_fixture

/datum/unit_test/dq_p2_lights/damage_past_half_breaks_the_fixture/run_gate()
	var/obj/machinery/light/L = light()
	L.deal_damage(DAMAGE_BLUNT, 5)
	settle()
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_OK, "a light blow does not break it")
	L.deal_damage(DAMAGE_BLUNT, 8)
	settle()
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_BROKEN, "a second blow past half does")
	TEST_ASSERT(!L.on, "dark")

/// A creature smashing at a fixture breaks it; an empty or broken one is no use to it.
/datum/unit_test/dq_p2_lights/creature_smashes_a_fixture

/datum/unit_test/dq_p2_lights/creature_smashes_a_fixture/run_gate()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	generic_hit(L, H, 15)
	settle()
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_BROKEN, "smashed")

/// A power surge blows a fixture.
/datum/unit_test/dq_p2_lights/surge_blows_a_fixture

/datum/unit_test/dq_p2_lights/surge_blows_a_fixture/run_gate()
	var/obj/machinery/light/L = light()
	L.surge_break()
	settle()
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_BROKEN, "blown")

/// A rigged fixture explodes the next time it lights.
/datum/unit_test/dq_p2_lights/rigged_fixture_explodes_when_it_lights_again

/datum/unit_test/dq_p2_lights/rigged_fixture_explodes_when_it_lights_again/run_gate()
	var/obj/machinery/light/L = light(/obj/machinery/light, tile(4, 4))
	L.rigged = 1
	set_area_switch(0)
	set_area_switch(1)
	TEST_ASSERT(QDELETED(L), "the fixture exploded")

/// A tube that has been switched very many times burns out sooner or later.
/datum/unit_test/dq_p2_lights/an_overused_tube_burns_out

/datum/unit_test/dq_p2_lights/an_overused_tube_burns_out/run_gate()
	var/obj/machinery/light/L = light()
	p2l_set_switchcount(L, 100000)
	for(var/i in 1 to 40)
		set_area_switch(0)
		set_area_switch(1)
		if(p2l_status(L) == LIGHT_BURNED)
			break
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_BURNED, "burned out")
	TEST_ASSERT(!L.on, "dark")

/// A fresh tube does not burn out however it is switched.
/datum/unit_test/dq_p2_lights/a_fresh_tube_does_not_burn_out

/datum/unit_test/dq_p2_lights/a_fresh_tube_does_not_burn_out/run_gate()
	var/obj/machinery/light/L = light()
	for(var/i in 1 to 12)
		set_area_switch(0)
		set_area_switch(1)
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_OK, "still whole")
	TEST_ASSERT(L.on, "lit")

// ---------------------------------------------------------------------------------------------------------------------
// The floor lamp, the torch, the fairy lights
// ---------------------------------------------------------------------------------------------------------------------

/// A floor lamp with a shade is toggled by a bare hand; the bulb stays in.
/datum/unit_test/dq_p2_lights/floor_lamp_with_a_shade_toggles_by_hand

/datum/unit_test/dq_p2_lights/floor_lamp_with_a_shade_toggles_by_hand/run_gate()
	var/obj/machinery/light/flamp/F = light(/obj/machinery/light/flamp)
	var/mob/living/carbon/human/H = person()
	TEST_ASSERT(F.lamp_shade, "it has a shade")
	TEST_ASSERT(F.on, "lit")
	click(H, F, null)
	TEST_ASSERT(!F.on, "switched off")
	TEST_ASSERT_EQUAL(p2l_status(F), LIGHT_OK, "its bulb is still in")
	click(H, F, null)
	TEST_ASSERT(F.on, "switched on again")

/// A floor lamp without a shade gives its bulb to a bare hand.
/datum/unit_test/dq_p2_lights/floor_lamp_without_a_shade_gives_up_its_bulb

/datum/unit_test/dq_p2_lights/floor_lamp_without_a_shade_gives_up_its_bulb/run_gate()
	var/obj/machinery/light/flamp/F = light(/obj/machinery/light/flamp)
	var/mob/living/carbon/human/H = gloved(person())
	F.lamp_shade = 0
	click(H, F, null)
	TEST_ASSERT_EQUAL(p2l_status(F), LIGHT_EMPTY, "the bulb came out")
	TEST_ASSERT(istype(H.get_active_hand(), /obj/item/light/bulb/large), "into the hand")

/// A screwdriver takes the shade off a lamp and a shade goes back on a bare one.
/datum/unit_test/dq_p2_lights/screwdriver_takes_the_shade_off_and_a_shade_goes_back_on

/datum/unit_test/dq_p2_lights/screwdriver_takes_the_shade_off_and_a_shade_goes_back_on/run_gate()
	var/obj/machinery/light/flamp/F = light(/obj/machinery/light/flamp)
	var/mob/living/carbon/human/H = person()
	var/turf/T = F.loc
	click(H, F, tool(/obj/item/tool/screwdriver))
	TEST_ASSERT(!F.lamp_shade, "the shade is off")
	var/obj/item/lampshade/S = locate(/obj/item/lampshade) in T
	TEST_ASSERT(istype(S), "the shade lies on the floor")
	click(H, F, S)
	TEST_ASSERT(F.lamp_shade, "the shade is on again")
	TEST_ASSERT(QDELETED(S), "the shade was used up")

/// A wrench unbolts and bolts a floor lamp.
/datum/unit_test/dq_p2_lights/wrench_unbolts_and_bolts_a_floor_lamp

/datum/unit_test/dq_p2_lights/wrench_unbolts_and_bolts_a_floor_lamp/run_gate()
	var/obj/machinery/light/flamp/F = light(/obj/machinery/light/flamp)
	var/mob/living/carbon/human/H = person()
	var/obj/item/tool/wrench/W = tool(/obj/item/tool/wrench)
	TEST_ASSERT(F.anchored, "bolted to begin with")
	click(H, F, W)
	TEST_ASSERT(!F.anchored, "unbolted")
	click(H, F, W)
	TEST_ASSERT(F.anchored, "bolted again")

/// A lamp with a shade ignores the area's light switch; one without obeys it.
/datum/unit_test/dq_p2_lights/shaded_floor_lamp_ignores_the_area_switch

/datum/unit_test/dq_p2_lights/shaded_floor_lamp_ignores_the_area_switch/run_gate()
	var/obj/machinery/light/flamp/F = light(/obj/machinery/light/flamp, tile(1, 3))
	var/obj/machinery/light/flamp/N = light(/obj/machinery/light/flamp, tile(3, 3))
	N.lamp_shade = 0
	set_area_switch(0)
	TEST_ASSERT(F.on, "a shaded lamp stays lit")
	TEST_ASSERT(!N.on, "a bare lamp goes dark")

/// A wall torch swallows whatever is used on it.
/datum/unit_test/dq_p2_lights/torch_swallows_what_is_used_on_it

/datum/unit_test/dq_p2_lights/torch_swallows_what_is_used_on_it/run_gate()
	var/obj/machinery/light/small/torch/T = light(/obj/machinery/light/small/torch)
	var/mob/living/carbon/human/H = person()
	var/obj/item/I = allocate(/obj/item, tile(0, 1))
	I.force = 30
	click(H, T, I, I_HURT)
	TEST_ASSERT_EQUAL(p2l_status(T), LIGHT_OK, "not smashed")
	p2l_make_empty(T)
	settle()
	var/obj/item/light/B = bulb(/obj/item/light/bulb/torch)
	click(H, T, B)
	TEST_ASSERT_EQUAL(p2l_status(T), LIGHT_EMPTY, "a torch takes no bulb")

// ---------------------------------------------------------------------------------------------------------------------
// The light item
// ---------------------------------------------------------------------------------------------------------------------

/// The picture of a light shows its state.
/proc/p2l_item_icon(obj/item/light/B)
	B.update_icon()
	refresh_flush()
	return B.icon_state

/// The tube's icon and state follow its status.
/datum/unit_test/dq_p2_lights/light_item_shows_its_status

/datum/unit_test/dq_p2_lights/light_item_shows_its_status/run_gate()
	var/obj/item/light/tube/B = bulb()
	TEST_ASSERT_EQUAL(p2l_item_icon(B), "ltube", "a whole tube")
	B.set_status(LIGHT_BURNED)
	TEST_ASSERT_EQUAL(p2l_item_icon(B), "ltube-burned", "a burned tube")
	B.set_status(LIGHT_BROKEN)
	TEST_ASSERT_EQUAL(p2l_item_icon(B), "ltube-broken", "a broken tube")

/// A thrown light shatters when it lands.
/datum/unit_test/dq_p2_lights/thrown_light_shatters

/datum/unit_test/dq_p2_lights/thrown_light_shatters/run_gate()
	var/obj/item/light/tube/B = bulb()
	B.throw_impact(tile(1, 1))
	TEST_ASSERT_EQUAL(B.status, LIGHT_BROKEN, "broken")
	TEST_ASSERT(B.sharp, "sharp")
	TEST_ASSERT_EQUAL(B.force, 5, "it cuts")

/// A broken light does not shatter twice.
/datum/unit_test/dq_p2_lights/broken_light_stays_broken

/datum/unit_test/dq_p2_lights/broken_light_stays_broken/run_gate()
	var/obj/item/light/tube/B = bulb(/obj/item/light/tube, LIGHT_BROKEN)
	B.force = 2
	B.throw_impact(tile(1, 1))
	TEST_ASSERT_EQUAL(B.force, 2, "nothing changed")

/// A light used to hit something in a harm stance shatters; in any other stance it does not; against a fixture it does not.
/datum/unit_test/dq_p2_lights/light_hit_in_harm_stance_shatters

/datum/unit_test/dq_p2_lights/light_hit_in_harm_stance_shatters/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/light/tube/B = bulb()
	var/obj/machinery/light/L = light(/obj/machinery/light, tile(3, 3))
	click(H, L, B, I_HURT)
	TEST_ASSERT_EQUAL(B.status, LIGHT_OK, "a hit on a fixture does not shatter it")
	click(H, tile(2, 1), B, I_HELP)
	TEST_ASSERT_EQUAL(B.status, LIGHT_OK, "a help click on the floor does not")
	click(H, tile(2, 1), B, I_HURT)
	TEST_ASSERT_EQUAL(B.status, LIGHT_BROKEN, "a harm click on the floor does")

/// A syringe of phoron rigs a light to explode; any syringe is emptied into it.
/datum/unit_test/dq_p2_lights/phoron_syringe_rigs_a_light

/datum/unit_test/dq_p2_lights/phoron_syringe_rigs_a_light/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/light/tube/B = bulb()
	var/obj/item/reagent_containers/syringe/S = allocate(/obj/item/reagent_containers/syringe, tile(0, 1))
	S.reagents.add_reagent(REAGENT_ID_PHORON, 5)
	click(H, B, S)
	TEST_ASSERT(B.rigged, "rigged")
	TEST_ASSERT_EQUAL(S.reagents.total_volume, 0, "the syringe is emptied")
	var/obj/item/light/tube/C = bulb()
	var/obj/item/reagent_containers/syringe/W = allocate(/obj/item/reagent_containers/syringe, tile(0, 1))
	W.reagents.add_reagent(REAGENT_ID_WATER, 5)
	click(H, C, W)
	TEST_ASSERT(!C.rigged, "water does not rig it")
	TEST_ASSERT_EQUAL(W.reagents.total_volume, 0, "but the syringe is emptied all the same")

// ---------------------------------------------------------------------------------------------------------------------
// The fixture frames
// ---------------------------------------------------------------------------------------------------------------------

/// A frame as the builder leaves it: bare (stage 1).
/datum/unit_test/dq_p2_lights/proc/frame(type = /obj/machinery/light_construct, turf/T)
	var/obj/machinery/light_construct/C = allocate(type, T || tile(2, 2))
	settle()
	return C

/// A coil of cable of `amount` lengths.
/datum/unit_test/dq_p2_lights/proc/coil(amount = 5)
	return allocate(/obj/item/stack/cable_coil, tile(0, 1), amount)

/// The bare frame takes a length of cable and is wired.
/datum/unit_test/dq_p2_lights/cable_wires_a_bare_frame

/datum/unit_test/dq_p2_lights/cable_wires_a_bare_frame/run_gate()
	var/obj/machinery/light_construct/C = frame()
	var/mob/living/carbon/human/H = person()
	var/obj/item/stack/cable_coil/W = coil()
	TEST_ASSERT_EQUAL(p2l_stage(C), 1, "bare")
	click(H, C, W)
	TEST_ASSERT_EQUAL(p2l_stage(C), 2, "wired")
	TEST_ASSERT_EQUAL(W.amount, 4, "one length used")

/// A frame that is already wired does not take more.
/datum/unit_test/dq_p2_lights/wired_frame_takes_no_more_cable

/datum/unit_test/dq_p2_lights/wired_frame_takes_no_more_cable/run_gate()
	var/obj/machinery/light_construct/C = frame()
	var/mob/living/carbon/human/H = person()
	var/obj/item/stack/cable_coil/W = coil()
	click(H, C, W)
	click(H, C, W)
	TEST_ASSERT_EQUAL(p2l_stage(C), 2, "still wired")
	TEST_ASSERT_EQUAL(W.amount, 4, "no more used")

/// Wirecutters take the wire back off: the frame is bare and a length of cable lies on the floor.
/datum/unit_test/dq_p2_lights/wirecutters_unwire_a_frame

/datum/unit_test/dq_p2_lights/wirecutters_unwire_a_frame/run_gate()
	var/obj/machinery/light_construct/C = frame()
	var/mob/living/carbon/human/H = person()
	var/turf/T = C.loc
	click(H, C, coil())
	click(H, C, tool(/obj/item/tool/wirecutters))
	TEST_ASSERT_EQUAL(p2l_stage(C), 1, "bare again")
	var/obj/item/stack/cable_coil/dropped = locate(/obj/item/stack/cable_coil) in T
	TEST_ASSERT(istype(dropped), "a coil on the floor")
	qdel(dropped)

/// Wirecutters on a bare frame do nothing.
/datum/unit_test/dq_p2_lights/wirecutters_do_nothing_to_a_bare_frame

/datum/unit_test/dq_p2_lights/wirecutters_do_nothing_to_a_bare_frame/run_gate()
	var/obj/machinery/light_construct/C = frame()
	var/mob/living/carbon/human/H = person()
	var/turf/T = C.loc
	click(H, C, tool(/obj/item/tool/wirecutters))
	TEST_ASSERT_EQUAL(p2l_stage(C), 1, "still bare")
	TEST_ASSERT(!(locate(/obj/item/stack/cable_coil) in T), "no cable")

/// A screwdriver closes a wired frame into an empty fixture of its kind, facing the same way, and the frame is gone.
/datum/unit_test/dq_p2_lights/screwdriver_closes_a_wired_frame_into_a_fixture

/datum/unit_test/dq_p2_lights/screwdriver_closes_a_wired_frame_into_a_fixture/run_gate()
	var/obj/machinery/light_construct/small/C = frame(/obj/machinery/light_construct/small)
	var/mob/living/carbon/human/H = person()
	C.set_dir(WEST)
	var/turf/T = C.loc
	click(H, C, coil())
	click(H, C, tool(/obj/item/tool/screwdriver))
	TEST_ASSERT(QDELETED(C), "the frame is gone")
	var/obj/machinery/light/small/L = locate(/obj/machinery/light/small) in T
	TEST_ASSERT(istype(L), "a small fixture stands there")
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_EMPTY, "empty")
	TEST_ASSERT_EQUAL(L.dir, WEST, "facing as the frame faced")
	TEST_ASSERT(p2l_has_cell(L), "a fixture of its own kind comes with its cell, whatever the frame held")
	TEST_ASSERT(L.construct_type == /obj/machinery/light_construct/small, "it opens back into the same frame")
	qdel(L)

/// The cell the fixture ends up with after a frame that held `cell` is closed into it: the legacy code moves the cell into the fixture but loses the
/// link (`cell` stays null: the cell is orphaned in its contents), so a fixture built that way has none; the converted frame hands it over.
/proc/p2l_cell_after_closing(obj/item/cell/emergency_light/cell)
	return cell

/// The cell in the frame becomes the fixture's emergency cell.
/datum/unit_test/dq_p2_lights/the_frame_cell_becomes_the_fixture_cell

/datum/unit_test/dq_p2_lights/the_frame_cell_becomes_the_fixture_cell/run_gate()
	var/obj/machinery/light_construct/C = frame()
	var/mob/living/carbon/human/H = person()
	var/turf/T = C.loc
	var/obj/item/cell/emergency_light/E = allocate(/obj/item/cell/emergency_light, tile(0, 1))
	click(H, C, E)
	TEST_ASSERT(p2l_frame_cell(C) == E, "the frame holds the cell")
	click(H, C, coil())
	click(H, C, tool(/obj/item/tool/screwdriver))
	var/obj/machinery/light/L = locate(/obj/machinery/light) in T
	var/list/seen = list()
	for(var/atom/movable/AM in T)
		seen += "[AM.type]"
	TEST_ASSERT(istype(L), "a fixture (frame deleted [QDELETED(C)], on the tile [jointext(seen, ", ")])")
	TEST_ASSERT(p2l_cell(L) == p2l_cell_after_closing(E), "the fixture's emergency cell is what closing the frame hands over (cell [p2l_cell(L)])")
	qdel(L)

/// A screwdriver on a bare frame does nothing.
/datum/unit_test/dq_p2_lights/screwdriver_does_nothing_to_a_bare_frame

/datum/unit_test/dq_p2_lights/screwdriver_does_nothing_to_a_bare_frame/run_gate()
	var/obj/machinery/light_construct/C = frame()
	var/mob/living/carbon/human/H = person()
	click(H, C, tool(/obj/item/tool/screwdriver))
	TEST_ASSERT(!QDELETED(C), "still a frame")
	TEST_ASSERT_EQUAL(p2l_stage(C), 1, "still bare")

/// A wrench takes a bare frame apart into the sheets it was made of.
/datum/unit_test/dq_p2_lights/wrench_takes_a_bare_frame_apart_into_sheets

/datum/unit_test/dq_p2_lights/wrench_takes_a_bare_frame_apart_into_sheets/run_gate()
	var/list/expected = list(
		/obj/machinery/light_construct = 2,
		/obj/machinery/light_construct/small = 1,
		/obj/machinery/light_construct/flamp = 2,
		/obj/machinery/light_construct/floortube = 2,
		/obj/machinery/light_construct/bigfloorlamp = 3)
	var/mob/living/carbon/human/H = person()
	var/obj/item/tool/wrench/W = tool(/obj/item/tool/wrench)
	for(var/type in expected)
		var/turf/T = tile(4, 1)
		var/obj/machinery/light_construct/C = frame(type, T)
		click(H, C, W)
		TEST_ASSERT(QDELETED(C), "[type] came apart")
		var/obj/item/stack/material/steel/sheets = locate(/obj/item/stack/material/steel) in T
		TEST_ASSERT(istype(sheets), "[type] left steel")
		TEST_ASSERT_EQUAL(sheets.amount, expected[type], "[type] refunds its sheets")
		qdel(sheets)

/// A wired frame cannot be taken apart with a wrench.
/datum/unit_test/dq_p2_lights/wrench_refuses_a_wired_frame

/datum/unit_test/dq_p2_lights/wrench_refuses_a_wired_frame/run_gate()
	var/obj/machinery/light_construct/C = frame()
	var/mob/living/carbon/human/H = person()
	click(H, C, coil())
	click(H, C, tool(/obj/item/tool/wrench))
	TEST_ASSERT(!QDELETED(C), "still standing")
	TEST_ASSERT_EQUAL(p2l_stage(C), 2, "still wired")

/// A frame takes one emergency cell, gives it to a bare hand, and takes no other kind of cell.
/datum/unit_test/dq_p2_lights/frame_takes_gives_and_refuses_cells

/datum/unit_test/dq_p2_lights/frame_takes_gives_and_refuses_cells/run_gate()
	var/obj/machinery/light_construct/C = frame()
	var/mob/living/carbon/human/H = person()
	var/obj/item/cell/plain = allocate(/obj/item/cell, tile(0, 1))
	click(H, C, plain)
	TEST_ASSERT_NULL(p2l_frame_cell(C), "an ordinary cell does not fit")
	var/obj/item/cell/emergency_light/E = allocate(/obj/item/cell/emergency_light, tile(0, 1))
	var/obj/item/cell/emergency_light/F = allocate(/obj/item/cell/emergency_light, tile(0, 1))
	click(H, C, E)
	TEST_ASSERT(p2l_frame_cell(C) == E, "the emergency cell is in")
	click(H, C, F)
	TEST_ASSERT(p2l_frame_cell(C) == E, "a second is refused (cell [p2l_frame_cell(C)] E loc [E.loc] F loc [F.loc])")
	click(H, C, null)
	TEST_ASSERT_NULL(p2l_frame_cell(C), "a hand takes it out (operable [C.operable()])")
	TEST_ASSERT(H.get_active_hand() == E, "into the hand")

// ---------------------------------------------------------------------------------------------------------------------
// The light switch
// ---------------------------------------------------------------------------------------------------------------------

/// A switch in the room.
/datum/unit_test/dq_p2_lights/proc/light_switch(turf/T)
	var/obj/machinery/light_switch/S = allocate(/obj/machinery/light_switch, T || tile(4, 2))
	settle()
	return S

/// A placed switch shows the area's state.
/datum/unit_test/dq_p2_lights/switch_shows_the_area_state

/datum/unit_test/dq_p2_lights/switch_shows_the_area_state/run_gate()
	var/obj/machinery/light_switch/S = light_switch()
	TEST_ASSERT(S.on, "on with the area's lights on")
	TEST_ASSERT(p2l_switch_area(S) == p2l_area, "it works its own area")

/// A hand on the switch turns the area's lights off and on.
/datum/unit_test/dq_p2_lights/hand_toggles_the_areas_lights

/datum/unit_test/dq_p2_lights/hand_toggles_the_areas_lights/run_gate()
	var/obj/machinery/light_switch/S = light_switch()
	var/obj/machinery/light/L = light()
	var/mob/living/carbon/human/H = person()
	var/count = GLOB.lights_switched_on_roundstat
	click(H, S, null)
	TEST_ASSERT(!p2l_area.lightswitch, "the area's switch is off")
	TEST_ASSERT(!S.on, "the switch shows it")
	TEST_ASSERT(!L.on, "the light is dark")
	TEST_ASSERT_EQUAL(GLOB.lights_switched_on_roundstat, count + 1, "the round counts a use")
	click(H, S, null)
	TEST_ASSERT(p2l_area.lightswitch, "on again")
	TEST_ASSERT(L.on, "the light is lit")

/// Two switches of an area show the same state.
/datum/unit_test/dq_p2_lights/switches_of_an_area_follow_each_other

/datum/unit_test/dq_p2_lights/switches_of_an_area_follow_each_other/run_gate()
	var/obj/machinery/light_switch/S = light_switch(tile(4, 2))
	var/obj/machinery/light_switch/T = light_switch(tile(4, 3))
	var/mob/living/carbon/human/H = person()
	click(H, S, null)
	TEST_ASSERT(!T.on, "the other switch went off too")
	click(H, T, null)
	TEST_ASSERT(S.on, "and back on from the other")

/// A switch is unpowered while its area's light channel is.
/datum/unit_test/dq_p2_lights/switch_follows_the_light_channel

/datum/unit_test/dq_p2_lights/switch_follows_the_light_channel/run_gate()
	var/obj/machinery/light_switch/S = light_switch()
	TEST_ASSERT(!p2l_switch_unpowered(S), "powered")
	set_area_power(FALSE)
	TEST_ASSERT(p2l_switch_unpowered(S), "unpowered with the channel")
	set_area_power(TRUE)
	TEST_ASSERT(!p2l_switch_unpowered(S), "powered again")

/// An EMP makes a switch read its power again.
/datum/unit_test/dq_p2_lights/emp_makes_a_switch_read_its_power

/datum/unit_test/dq_p2_lights/emp_makes_a_switch_read_its_power/run_gate()
	var/obj/machinery/light_switch/S = light_switch()
	p2l_area.power_light = FALSE // the area's channel went down without the switch being told
	S.emp_act(1)
	settle()
	TEST_ASSERT(p2l_switch_unpowered(S), "it read the channel")

// ---------------------------------------------------------------------------------------------------------------------
// The light switch frame
// ---------------------------------------------------------------------------------------------------------------------

/// A switch frame on the wall (unfastened).
/datum/unit_test/dq_p2_lights/proc/switch_frame(turf/T)
	var/obj/structure/construction/lightswitch/C = allocate(/obj/structure/construction/lightswitch, T || tile(4, 2), SOUTH, TRUE)
	settle()
	return C

/// A screwdriver fastens and unfastens the frame.
/datum/unit_test/dq_p2_lights/switch_frame_is_fastened_and_unfastened_with_a_screwdriver

/datum/unit_test/dq_p2_lights/switch_frame_is_fastened_and_unfastened_with_a_screwdriver/run_gate()
	var/obj/structure/construction/lightswitch/C = switch_frame()
	var/mob/living/carbon/human/H = person()
	var/obj/item/tool/screwdriver/D = tool(/obj/item/tool/screwdriver)
	TEST_ASSERT_EQUAL(p2l_switch_stage(C), FRAME_UNFASTENED, "unfastened")
	click(H, C, D)
	TEST_ASSERT_EQUAL(p2l_switch_stage(C), FRAME_FASTENED, "fastened")
	click(H, C, D)
	TEST_ASSERT_EQUAL(p2l_switch_stage(C), FRAME_UNFASTENED, "unfastened again")

/// Cable wires a fastened frame only; wirecutters take it off again and drop a length.
/datum/unit_test/dq_p2_lights/switch_frame_takes_cable_only_when_fastened

/datum/unit_test/dq_p2_lights/switch_frame_takes_cable_only_when_fastened/run_gate()
	var/obj/structure/construction/lightswitch/C = switch_frame()
	var/mob/living/carbon/human/H = person()
	var/turf/T = C.loc
	var/obj/item/stack/cable_coil/W = coil()
	click(H, C, W)
	TEST_ASSERT_EQUAL(p2l_switch_stage(C), FRAME_UNFASTENED, "an unfastened frame is not wired")
	TEST_ASSERT_EQUAL(W.amount, 5, "no cable used")
	click(H, C, tool(/obj/item/tool/screwdriver))
	click(H, C, W)
	TEST_ASSERT_EQUAL(p2l_switch_stage(C), FRAME_WIRED, "wired")
	TEST_ASSERT_EQUAL(W.amount, 4, "one length used")
	click(H, C, tool(/obj/item/tool/wirecutters))
	TEST_ASSERT_EQUAL(p2l_switch_stage(C), FRAME_FASTENED, "the wire is off")
	var/obj/item/stack/cable_coil/dropped = locate(/obj/item/stack/cable_coil) in T
	TEST_ASSERT(istype(dropped), "a length of cable lies there")
	qdel(dropped)

/// A screwdriver on a wired frame builds the light switch where the frame was, with the frame's position.
/datum/unit_test/dq_p2_lights/switch_frame_closes_into_a_switch

/datum/unit_test/dq_p2_lights/switch_frame_closes_into_a_switch/run_gate()
	var/obj/structure/construction/lightswitch/C = switch_frame()
	var/mob/living/carbon/human/H = person()
	var/turf/T = C.loc
	var/px = C.pixel_x
	var/py = C.pixel_y
	click(H, C, tool(/obj/item/tool/screwdriver))
	click(H, C, coil())
	click(H, C, tool(/obj/item/tool/screwdriver))
	TEST_ASSERT(QDELETED(C), "the frame is gone")
	var/obj/machinery/light_switch/S = locate(/obj/machinery/light_switch) in T
	TEST_ASSERT(istype(S), "a switch stands there")
	TEST_ASSERT_EQUAL(S.pixel_x, px, "on the same wall")
	TEST_ASSERT_EQUAL(S.pixel_y, py, "at the same height")
	qdel(S)

/// A welder takes an unfastened frame down into two steel sheets, and refuses a fastened one.
/datum/unit_test/dq_p2_lights/welder_takes_an_unfastened_switch_frame_down

/datum/unit_test/dq_p2_lights/welder_takes_an_unfastened_switch_frame_down/run_gate()
	var/obj/structure/construction/lightswitch/C = switch_frame()
	var/mob/living/carbon/human/H = person()
	var/turf/T = C.loc
	click(H, C, tool(/obj/item/tool/screwdriver))
	click(H, C, dq_fueled_welder(tile(0, 1)))
	TEST_ASSERT(!QDELETED(C), "a fastened frame is not welded down")
	click(H, C, tool(/obj/item/tool/screwdriver))
	click(H, C, dq_fueled_welder(tile(0, 1)))
	TEST_ASSERT(QDELETED(C), "an unfastened frame comes down")
	var/obj/item/stack/material/steel/sheets = locate(/obj/item/stack/material/steel) in T
	TEST_ASSERT(istype(sheets), "steel")
	TEST_ASSERT_EQUAL(sheets.amount, 2, "two sheets")
	qdel(sheets)

/// A switch taken apart leaves a wired frame in its place.
/datum/unit_test/dq_p2_lights/dismantled_switch_leaves_a_wired_frame

/datum/unit_test/dq_p2_lights/dismantled_switch_leaves_a_wired_frame/run_gate()
	var/obj/machinery/light_switch/S = light_switch()
	var/turf/T = S.loc
	S.dismantle()
	settle()
	TEST_ASSERT(QDELETED(S), "the switch is gone")
	var/obj/structure/construction/lightswitch/C = locate(/obj/structure/construction/lightswitch) in T
	TEST_ASSERT(istype(C), "a frame")
	TEST_ASSERT_EQUAL(p2l_switch_stage(C), FRAME_WIRED, "wired")
	qdel(C)

// ---------------------------------------------------------------------------------------------------------------------
// The light replacer
// ---------------------------------------------------------------------------------------------------------------------

/// A light replacer with `uses` lights.
/datum/unit_test/dq_p2_lights/proc/replacer(uses = 10)
	var/obj/item/lightreplacer/R = allocate(/obj/item/lightreplacer, tile(3, 3))
	R.set_uses(uses)
	return R

/// A glass sheet makes sixteen lights, up to the replacer's limit.
/datum/unit_test/dq_p2_lights/glass_refills_a_light_replacer

/datum/unit_test/dq_p2_lights/glass_refills_a_light_replacer/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/lightreplacer/R = replacer(8)
	var/obj/item/stack/material/glass/G = allocate(/obj/item/stack/material/glass, tile(0, 1), 3)
	click(H, R, G)
	TEST_ASSERT_EQUAL(R.uses, 24, "sixteen lights for a sheet")
	TEST_ASSERT_EQUAL(G.amount, 2, "one sheet used")
	R.set_uses(R.max_uses)
	click(H, R, G)
	TEST_ASSERT_EQUAL(G.amount, 2, "a full replacer takes no glass")

/// A working tube is a light for the replacer; a full one leaves it be.
/datum/unit_test/dq_p2_lights/working_tube_refills_a_light_replacer

/datum/unit_test/dq_p2_lights/working_tube_refills_a_light_replacer/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/lightreplacer/R = replacer(10)
	var/obj/item/light/B = bulb()
	click(H, R, B)
	TEST_ASSERT_EQUAL(R.uses, 11, "one more light")
	TEST_ASSERT(QDELETED(B), "the tube was taken in")
	R.set_uses(R.max_uses)
	var/obj/item/light/C = bulb()
	click(H, R, C)
	TEST_ASSERT(!QDELETED(C), "a full replacer leaves the tube alone")

/// Four broken tubes make one light.
/datum/unit_test/dq_p2_lights/broken_tubes_make_a_light_in_fours

/datum/unit_test/dq_p2_lights/broken_tubes_make_a_light_in_fours/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/lightreplacer/R = replacer(10)
	for(var/i in 1 to 3)
		click(H, R, bulb(/obj/item/light/tube, LIGHT_BROKEN))
	TEST_ASSERT_EQUAL(R.uses, 10, "three shards are not a light")
	TEST_ASSERT_EQUAL(R.bulb_shards, 3, "three shards kept")
	click(H, R, bulb(/obj/item/light/tube, LIGHT_BURNED))
	TEST_ASSERT_EQUAL(R.uses, 11, "the fourth makes one")
	TEST_ASSERT_EQUAL(R.bulb_shards, 0, "no shards left")

/// A box of lights fills a replacer from the working tubes in it.
/datum/unit_test/dq_p2_lights/box_of_lights_fills_a_light_replacer

/datum/unit_test/dq_p2_lights/box_of_lights_fills_a_light_replacer/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/lightreplacer/R = replacer(0)
	var/obj/item/storage/box/lights/tubes/box = allocate(/obj/item/storage/box/lights/tubes, tile(0, 1))
	click(H, R, box)
	TEST_ASSERT(R.uses > 0, "lights from the box")

/// The replacer swaps a broken fixture's tube for a new one of the chosen colour and keeps the glass as shards.
/datum/unit_test/dq_p2_lights/replacer_replaces_a_broken_tube

/datum/unit_test/dq_p2_lights/replacer_replaces_a_broken_tube/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/lightreplacer/R = replacer(10)
	R.selected_color = "#ff00ff"
	var/obj/machinery/light/L = light()
	L.broken()
	settle()
	click(H, L, R)
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_OK, "a whole tube")
	TEST_ASSERT(L.on, "lit")
	TEST_ASSERT_EQUAL(L.light_color, "#ff00ff", "the chosen colour")
	TEST_ASSERT_EQUAL(R.uses, 9, "one light used")
	TEST_ASSERT_EQUAL(R.bulb_shards, 1, "the broken tube is kept as a shard")

/// The replacer fills an empty fixture without taking a shard.
/datum/unit_test/dq_p2_lights/replacer_fills_an_empty_fixture

/datum/unit_test/dq_p2_lights/replacer_fills_an_empty_fixture/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/lightreplacer/R = replacer(10)
	var/obj/machinery/light/L = light()
	p2l_make_empty(L)
	settle()
	click(H, L, R)
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_OK, "a tube")
	TEST_ASSERT_EQUAL(R.uses, 9, "one light used")
	TEST_ASSERT_EQUAL(R.bulb_shards, 0, "no shard from nothing")

/// The replacer leaves a working fixture, and does nothing when it is out of lights.
/datum/unit_test/dq_p2_lights/replacer_leaves_a_working_fixture_and_needs_lights

/datum/unit_test/dq_p2_lights/replacer_leaves_a_working_fixture_and_needs_lights/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/lightreplacer/R = replacer(10)
	var/obj/machinery/light/L = light()
	var/obj/item/light/first = p2l_bulb(L)
	click(H, L, R)
	TEST_ASSERT_EQUAL(R.uses, 10, "nothing used")
	TEST_ASSERT(p2l_bulb(L) == first, "the working tube is kept")
	L.broken()
	settle()
	R.set_uses(0)
	click(H, L, R)
	TEST_ASSERT_EQUAL(p2l_status(L), LIGHT_BROKEN, "no lights, no replacement")

/// An emag card toggles the replacer's emagged state, again and again.
/datum/unit_test/dq_p2_lights/emag_toggles_the_light_replacer

/datum/unit_test/dq_p2_lights/emag_toggles_the_light_replacer/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/lightreplacer/R = replacer()
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, tile(0, 1))
	TEST_ASSERT(!R.emagged, "clean")
	click(H, R, E)
	TEST_ASSERT(R.emagged, "emagged")
	click(H, R, E)
	TEST_ASSERT(!R.emagged, "a second swipe undoes it")

/// Using the replacer in hand asks for a colour for the lights it makes.
/datum/unit_test/dq_p2_lights/using_the_replacer_picks_a_colour

/datum/unit_test/dq_p2_lights/using_the_replacer_picks_a_colour/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/lightreplacer/R = replacer()
	p2l_click(H, R, R)
	p2l_answer(H, "#aa00aa")
	settle()
	TEST_ASSERT_EQUAL(R.selected_color, "#aa00aa", "the colour was picked")

// ---------------------------------------------------------------------------------------------------------------------
// The light painter
// ---------------------------------------------------------------------------------------------------------------------

/// A painter that resets colours sets a fixture back to the stock colours.
/datum/unit_test/dq_p2_lights/painter_resets_a_fixture_by_default

/datum/unit_test/dq_p2_lights/painter_resets_a_fixture_by_default/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/lightpainter/P = allocate(/obj/item/lightpainter, tile(0, 1))
	var/obj/machinery/light/L = light()
	L.brightness_color = "#123456"
	click(H, L, P)
	var/list/numbers = p2l_numbers(L)
	var/list/night = p2l_night_numbers(L)
	TEST_ASSERT_EQUAL(numbers[3], "#e0eff0", "the stock colour")
	TEST_ASSERT_EQUAL(night[3], "#efcc86", "the stock night colour")
	TEST_ASSERT_EQUAL(L.light_color, "#e0eff0", "the light shows it")
	TEST_ASSERT(L.on, "still lit")

/// A painter set to a colour paints a fixture with it, and its night colour is the dimmed one.
/datum/unit_test/dq_p2_lights/painter_paints_the_chosen_colour

/datum/unit_test/dq_p2_lights/painter_paints_the_chosen_colour/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/lightpainter/P = allocate(/obj/item/lightpainter, tile(0, 1))
	var/obj/machinery/light/L = light()
	p2l_click(H, P, P)
	p2l_answer(H, "#ff0000")
	settle()
	TEST_ASSERT(!P.resetmode, "no longer resetting")
	click(H, L, P)
	var/list/numbers = p2l_numbers(L)
	var/list/night = p2l_night_numbers(L)
	TEST_ASSERT_EQUAL(numbers[3], "#ff0000", "the chosen colour")
	TEST_ASSERT_EQUAL(night[3], P.setnightcolor, "the dimmed night colour")
	TEST_ASSERT_EQUAL(L.light_color, "#ff0000", "the light shows it")

/// Using a painter that is painting puts it back in reset mode.
/datum/unit_test/dq_p2_lights/using_a_painting_painter_resets_it

/datum/unit_test/dq_p2_lights/using_a_painting_painter_resets_it/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/lightpainter/P = allocate(/obj/item/lightpainter, tile(0, 1))
	P.set_resetmode(0)
	click(H, P, P)
	TEST_ASSERT(P.resetmode, "reset mode")
