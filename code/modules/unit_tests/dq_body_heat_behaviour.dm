// Behaviour pins for body heat against the room (doc/rewrite/temperature.md §3): a human in a real sealed room, its Life environment and
// thermoregulation stages run once per Life frame while the native world (gas, solids, heat links) steps a frame's seconds between them. Energy is
// conserved, so the room's air, floor and walls take what the body gives. The pre-heat numbers these pins keep (f24504821c, a detached
// mixture that never warmed, 6 s frames) are in doc/rewrite/intended_changes.md, "Body heat against the room"; each test logs what it measured.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

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
	for(var/turf/N as anything in ring)
		heat_set_solid(N, kelvin)
	SSair.run_gas_frames(1)
	return room

/// Every turf within `radius` of `centre` is a plain floor with air and nothing atmospheric on it.
/proc/body_heat_block_clear(turf/simulated/floor/centre, radius)
	if(centre.x <= radius + 1 || centre.y <= radius + 1 || centre.x + radius + 1 >= world.maxx || centre.y + radius + 1 >= world.maxy)
		return FALSE
	for(var/turf/T as anything in block(locate(centre.x - radius, centre.y - radius, centre.z), locate(centre.x + radius, centre.y + radius, centre.z)))
		if(!istype(T, /turf/simulated/floor) || T.blocks_air || !T.heat_has_air() || locate_within(T, /obj/machinery))
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
			life_test_environment(H, T.return_air())
			var/datum/om/stage/life/thermoregulation/thermo = om_stage_for(H, /datum/om/stage/life/thermoregulation)
			thermo.perform(H, null)
		SSair.run_gas_frames(LIFE_CYCLE_SECONDS) // the native world: the gas field, the floor and wall solids, the body's couplings and links
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
	dq_atmos_test_restore_state()

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

/// A crowd in an ordinary room does not warm it: inside their comfort range bodies trade no heat with the room, so a body that keeps its
/// temperature with no metabolic power has given the room nothing (before: the old code never heated air at all). The room's own drift (its
/// fresh walls settling with the floors) is logged, not judged.
/datum/unit_test/dq_body_heat/crowd_does_not_heat_room
	priority = TEST_LONGER

/datum/unit_test/dq_body_heat/crowd_does_not_heat_room/run_body_heat()
	var/list/room = body_heat_room(4, T20C)
	TEST_ASSERT_NOTNULL(room, "no clear 9x9 block for the room")
	var/list/people = list()
	for(var/i in 1 to 10)
		people += allocate(/mob/living/carbon/human, room[i])
	var/list/start = list()
	for(var/mob/living/carbon/human/H as anything in people)
		start[H] = H.body_temperature()
	var/before = body_heat_air_temperature(room)
	var/list/temps = body_heat_frames(people, 50)
	var/after = body_heat_air_temperature(room)
	log_frames("crowd", temps, "; room air [round(before, 0.01)] -> [round(after, 0.01)] K")
	for(var/mob/living/carbon/human/H as anything in people)
		var/conductance = H.body.environment_conductance + H.body.surface_conductance
		TEST_ASSERT(conductance == 0, "a body at ease is linked to the room ([H.body.environment_conductance] W/K air, [H.body.surface_conductance] W/K surface)")
		TEST_ASSERT(H.body.metabolic_power == 0, "a body at its set point makes heat ([H.body.metabolic_power] W)")
		TEST_ASSERT(abs(H.body_temperature() - start[H]) < 0.1, "a body at ease changed temperature ([start[H]] -> [H.body_temperature()] K)")

#endif
