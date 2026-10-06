// Behaviour pins for body heat against the room (doc/rewrite/temperature.md §3): a human in a real sealed room, its Life environment and
// thermoregulation stages run once per Life frame while the native world (gas, solids, heat links) steps a frame's seconds between them. Energy is
// conserved, so the room's air, floor and walls take what the body gives. The pre-heat numbers these pins keep (f24504821c, a detached
// mixture that never warmed, 6 s frames) are in doc/rewrite/intended_changes.md, "Body heat against the room"; each test logs what it measured.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Steps the native world (gas, solids, heat bodies' couplings, heat links) for `seconds` of world time, whatever its step length.
/proc/heat_test_world_seconds(seconds)
	SSair.run_gas_frames(max(1, round(seconds / SSvg.current_dt)))

/// A sealed square room of standard air, `radius` tiles from its centre, with its air, floor and walls at `kelvin`: its turfs, centre first,
/// or null when the map has no clear block that size.
/proc/body_heat_room(radius, kelvin)
	dq_atmos_test_restore_walls()
	var/turf/centre = null
	for(var/turf/simulated/floor/cand in world)
		if(body_heat_block_clear(cand, radius))
			centre = cand
			break
	if(!centre)
		return null
	var/list/room = list(centre)
	for(var/turf/T as anything in block(locate(centre.x - radius, centre.y - radius, centre.z), locate(centre.x + radius, centre.y + radius, centre.z)))
		if(T != centre)
			room += T
	// Wall the ring around it, and seal above and below.
	var/list/ring = list()
	for(var/turf/T as anything in block(locate(centre.x - radius - 1, centre.y - radius - 1, centre.z), locate(centre.x + radius + 1, centre.y + radius + 1, centre.z)))
		if(!(T in room))
			ring += T
	for(var/turf/T as anything in room)
		for(var/dir in list(UP, DOWN))
			var/turf/N = get_step_multiz(T, dir)
			if(N)
				ring += N
	for(var/turf/N as anything in ring)
		if(istype(N, /turf/simulated/wall) || N.blocks_air)
			continue
		GLOB.dq_atmos_test_walled_turfs[N] = N.type
		N.ChangeTurf(/turf/simulated/wall)
	SSair.run_gas_frames(1)
	for(var/turf/open/T as anything in room)
		dq_atmos_test_snapshot_air(T)
		dq_atmos_test_fill_standard_air(T, kelvin)
		heat_set_solid(T, kelvin)
		GLOB.body_heat_room_solids |= T
	for(var/turf/N as anything in ring)
		heat_set_solid(N, kelvin)
		GLOB.body_heat_room_solids |= N
	// The band outside the walls takes some of a hot room's heat through them: it goes back to how it was too.
	for(var/turf/B as anything in block(locate(centre.x - radius - 2, centre.y - radius - 2, centre.z), locate(centre.x + radius + 2, centre.y + radius + 2, centre.z)))
		if(!(B in room) && !(B in ring))
			GLOB.body_heat_room_solids |= B
			if(istype(B, /turf/open))
				dq_atmos_test_snapshot_air(B)
	SSair.run_gas_frames(1)
	return room

/// Turfs whose solid a room set: body_heat_room_restore() brings them back to room temperature, so the next test's room starts clean.
GLOBAL_LIST_EMPTY(body_heat_room_solids)

/proc/body_heat_room_restore()
	// The walls go back to what they were first (a turf keeps the temperature it was set to), then every solid the room set is at 20 °C.
	dq_atmos_test_restore_state()
	for(var/turf/T as anything in GLOB.body_heat_room_solids)
		if(T)
			T.initial_temperature = T20C // a turf the room walled registers again at its seed temperature: the seed too
			heat_set_solid(T, T20C)
	GLOB.body_heat_room_solids.Cut()

/// Every turf within `radius` of `centre` is a plain, empty floor with air.
/proc/body_heat_block_clear(turf/simulated/floor/centre, radius)
	if(centre.x <= radius + 1 || centre.y <= radius + 1 || centre.x + radius + 1 >= world.maxx || centre.y + radius + 1 >= world.maxy)
		return FALSE
	for(var/turf/T as anything in block(locate(centre.x - radius, centre.y - radius, centre.z), locate(centre.x + radius, centre.y + radius, centre.z)))
		if(!istype(T, /turf/simulated/floor) || T.blocks_air || !T.heat_has_air())
			return FALSE
		// Nothing that holds or makes heat of its own: a burning-room test would set it alight and it would warm the next test's room.
		if(locate_within(T, /obj/machinery) || locate_within(T, /obj/item) || locate_within(T, /obj/structure))
			return FALSE
	return TRUE

/// Mean air temperature of some turfs, K.
/proc/body_heat_air_temperature(list/turfs)
	. = 0
	for(var/turf/T as anything in turfs)
		var/datum/gas_mixture/air = T.return_air()
		. += air.return_temperature()
	. /= max(1, length(turfs))

/// Runs `frames` Life frames of environment and thermoregulation for every human in `people`, the native world stepping one frame between them.
/// Returns list("frame N" = the first human's body temperature) at frames 1, 5, 10, 20, 50, 100.
/proc/body_heat_frames(list/people, frames)
	. = list()
	for(var/i in 1 to frames)
		for(var/mob/living/carbon/human/H as anything in people)
			var/turf/T = H.loc
			H.life_environment_exchange(T.return_air())
			H.life_thermoregulation()
		heat_test_world_seconds(LIFE_CYCLE_SECONDS) // the native world: the gas field, the floor and wall solids, the body's couplings and links
		if(i in list(1, 5, 10, 20, 50, 100))
			var/mob/living/carbon/human/first = people[1]
			.["frame [i]"] = round(first.body_temperature(), 0.1)

/datum/unit_test/dq_body_heat
	abstract_type = /datum/unit_test/dq_body_heat

/datum/unit_test/dq_body_heat/Run()
	test_driver_begin()
	test_rng(1)
	run_body_heat()
	test_driver_end()
	body_heat_room_restore()

/datum/unit_test/dq_body_heat/proc/run_body_heat()
	return

/datum/unit_test/dq_body_heat/proc/log_frames(label, list/temps, extra = "")
	var/list/parts = list()
	for(var/key in temps)
		parts += "[key] [temps[key]] K"
	log_test("[label]: [jointext(parts, ", ")] [extra]")

/// An unsuited human in a −50 °C room (air, floor and walls) is in cold-damage range within the old time scale: before, 273.7 K after 10
/// frames and 262.1 K after 20 (a minute and two), holding near 262.7 K.
/datum/unit_test/dq_body_heat/cold_room_chills
	priority = TEST_LONGER

/datum/unit_test/dq_body_heat/cold_room_chills/run_body_heat()
	var/list/room = body_heat_room(4, T0C - 50)
	TEST_ASSERT_NOTNULL(room, "no clear 9x9 block for the cold room")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, room[1])
	var/list/temps = body_heat_frames(list(H), 20)
	log_frames("cold room", temps, "; room air [round(body_heat_air_temperature(room), 0.1)] K, floor under it [round(H.loc.get_temperature(), 0.1)] K")
	TEST_ASSERT(temps["frame 10"] < 280, "the body chilled within a minute ([temps["frame 10"]] K after 10 frames)")
	TEST_ASSERT(temps["frame 20"] < 270, "the body neared the cold-damage range within two minutes ([temps["frame 20"]] K after 20 frames)")

/// A suited human in space keeps its temperature (before: 310.15 K after 100 frames, no injury).
/datum/unit_test/dq_body_heat/suited_in_space_survives

/datum/unit_test/dq_body_heat/suited_in_space_survives/run_body_heat()
	var/turf/space/S = null
	for(var/turf/space/cand in world)
		S = cand
		break
	TEST_ASSERT_NOTNULL(S, "no space turf")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, S)
	H.equip_to_slot_if_possible(new /obj/item/clothing/suit/space(H), SLOT_ID_SUIT, disable_warning = TRUE)
	H.equip_to_slot_if_possible(new /obj/item/clothing/head/helmet/space(H), SLOT_ID_HEAD, disable_warning = TRUE)
	var/injury0 = H.injury_load(INJURY_CATEGORY_THERMAL)
	var/list/temps = body_heat_frames(list(H), 100)
	var/injury = H.injury_load(INJURY_CATEGORY_THERMAL) - injury0
	log_frames("suited in space", temps, "; thermal injury [injury]")
	TEST_ASSERT(temps["frame 100"] > H.species.cold_discomfort_level, "the suited body stayed warm ([temps["frame 100"]] K)")
	TEST_ASSERT(injury <= 0, "the suited body took no thermal injury ([injury])")

/// A hot room heats an unsuited human toward its heat-damage range (before: 347.8 K after 10 frames and 357.7 K after 20 at 400 K air).
/datum/unit_test/dq_body_heat/hot_room_heats
	priority = TEST_LONGER

/datum/unit_test/dq_body_heat/hot_room_heats/run_body_heat()
	var/list/room = body_heat_room(4, 400)
	TEST_ASSERT_NOTNULL(room, "no clear 9x9 block for the hot room")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, room[1])
	var/list/temps = body_heat_frames(list(H), 20)
	log_frames("hot room", temps, "; room air [round(body_heat_air_temperature(room), 0.1)] K")
	TEST_ASSERT(temps["frame 20"] > 345, "the body heated ([temps["frame 20"]] K after 20 frames)")

/// A burning room (1000 K) burns an unsuited human at once (before: past its heat-damage level within 2 frames, thermal injury 392 after 100).
/datum/unit_test/dq_body_heat/fire_burns
	priority = TEST_LONGER

/datum/unit_test/dq_body_heat/fire_burns/run_body_heat()
	var/list/room = body_heat_room(4, 1000)
	TEST_ASSERT_NOTNULL(room, "no clear 9x9 block for the burning room")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, room[1])
	var/injury0 = H.injury_load(INJURY_CATEGORY_THERMAL)
	var/list/temps = body_heat_frames(list(H), 5)
	var/injury = H.injury_load(INJURY_CATEGORY_THERMAL) - injury0
	log_frames("burning room", temps, "; thermal injury [injury]")
	TEST_ASSERT(temps["frame 5"] > H.species.heat_level_1, "the body passed its heat-damage level within 5 frames ([temps["frame 5"]] K)")
	TEST_ASSERT(injury > 0, "the fire burned ([injury])")

/// A crowd in an ordinary room does not warm it: inside their comfort range (the air they stir within 20 K of the body, a safe pressure) bodies are linked to the room at
/// zero conductance, so they give it nothing (before: the old code never heated air at all). Judged every frame; the room's own drift, which
/// depends on what earlier tests left in the walls around it, is logged.
/datum/unit_test/dq_body_heat/crowd_does_not_heat_room
	priority = TEST_LONGER

/datum/unit_test/dq_body_heat/crowd_does_not_heat_room/run_body_heat()
	var/list/room = body_heat_room(4, T20C)
	TEST_ASSERT_NOTNULL(room, "no clear 9x9 block for the room")
	var/list/people = list()
	for(var/i in 1 to 10)
		people += allocate(/mob/living/carbon/human, room[i])
	var/before = body_heat_air_temperature(room)
	var/at_ease_frames = 0
	for(var/frame in 1 to 50)
		// Who is at ease is judged as Life sees it, before the frame runs.
		var/list/at_ease = list()
		for(var/mob/living/carbon/human/H as anything in people)
			var/datum/gas_mixture/air = H.loc.return_air()
			var/pressure = H.calculate_affecting_pressure(air.return_pressure())
			if(abs(H.life_environment_plume_temperature(H.loc, air) - H.body_temperature()) < 19 && pressure > H.species.warning_low_pressure && pressure < H.species.warning_high_pressure)
				at_ease += H
		body_heat_frames(people, 1)
		for(var/mob/living/carbon/human/H as anything in at_ease)
			at_ease_frames++
			var/conductance = H.body.environment_conductance + H.body.surface_conductance
			TEST_ASSERT(conductance == 0, "frame [frame]: a body at ease is linked to the room ([H.body.environment_conductance] W/K air, [H.body.surface_conductance] W/K surface)")
	var/after = body_heat_air_temperature(room)
	log_test("crowd: [at_ease_frames] body-frames at ease, all unlinked; room air [round(before, 0.01)] -> [round(after, 0.01)] K")
	TEST_ASSERT(at_ease_frames > 250, "the crowd was at ease most of the time ([at_ease_frames] of 500 body-frames)")

#endif
