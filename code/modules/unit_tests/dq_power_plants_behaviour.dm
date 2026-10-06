// Behaviour pins for the engineering power plants (the supermatter, the singularity and its containment, the tesla, fusion, the portable
// generators, the gravity generator, solars and the TEG's electrical side). They are SAFETY-CRITICAL: a delamination, a singularity escape and a
// containment failure are round-ending, so every curve and threshold the plants run on is pinned here, green on the legacy machine_step() code
// first, then kept green while each plant moves onto the final forms (every(), the power and heat domains).
//
// Rules: a plant's periodic work is run one step at a time through pp_step() (the adapter: the legacy machine_step(), or the converted step
// proc the plant's every() runs), so a pin states what ONE step does from a known state; the cadence pins run real time (test_time) instead.
// Numbers are recomputed in the test from the documented formula, independently of the code under test. Where a number changes on purpose,
// doc/rewrite/intended_changes.md ("Power plants") records it and the pin is edited in the same commit.

/// One step of a plant's periodic work: the converted step proc named `step` when the plant has it, else the legacy machine_step().
/proc/pp_step(datum/D, step)
	if(step && hascall(D, step))
		return call(D, step)(null)
	var/obj/machinery/M = D
	if(istype(M))
		return M.machine_step()
	return D.process()

/// Moles of `gas` in `air`.
/proc/pp_moles(datum/gas_mixture/air, gas)
	return air.get_moles(gas)

/// Thermal energy of a mixture, J.
/proc/pp_energy(datum/gas_mixture/air)
	return air.heat_capacity() * air.return_temperature()

/// TRUE when a and b agree to `rel` (relative) or `abs_tol` (absolute), whichever is looser.
/proc/pp_close(a, b, rel = 0.001, abs_tol = 0.0001)
	return abs(a - b) <= max(abs_tol, rel * max(abs(a), abs(b)))

/datum/unit_test/dq_pp
	abstract_type = /datum/unit_test/dq_pp

/datum/unit_test/dq_pp/Run()
	test_driver_begin()
	test_rng(1)
	run_pp()
	test_driver_end()
	dq_atmos_test_restore_walls()

/datum/unit_test/dq_pp/proc/run_pp()
	return

/// An isolated two-tile room holding only `o2` and `n2` moles at `kelvin`: list(plant tile, other tile).
/datum/unit_test/dq_pp/proc/pp_room(kelvin, o2 = MOLES_O2STANDARD, n2 = 0)
	var/list/pair = dq_atmos_test_find_clear_pipe_run(2)
	TEST_ASSERT_NOTNULL(pair, "no room for the plant")
	dq_atmos_test_isolate_pair(pair[1], pair[2])
	for(var/turf/open/T as anything in pair)
		T.air.clear()
		if(o2)
			T.air.set_moles(/datum/gas/oxygen, o2)
		if(n2)
			T.air.set_moles(/datum/gas/nitrogen, n2)
		heat_set(T.air, kelvin)
	return pair

// ============================================================================================ the supermatter

#define PP_SM_STEP "sm_step"
#define PP_SM_DECAY 700
#define PP_SM_CRITICAL 5000

/datum/unit_test/dq_pp/proc/pp_sm(turf/T, type = /obj/machinery/power/supermatter)
	var/obj/machinery/power/supermatter/SM = allocate(type, T)
	return SM

/// The power one step of a crystal at `p0` makes from removed gas at `t` K whose oxygen fraction (after nitrogen retardation) is `oxygen`,
/// before the radiation loss: the chain reaction's gain, equilibrium 400 above an oxygen fraction of 0.8 and 250 below.
/proc/pp_sm_gain(p0, t, oxygen)
	var/equilibrium = oxygen > 0.8 ? 400 : 250
	var/temp_factor = ((equilibrium / PP_SM_DECAY) ** 3) / 800
	return max(t * temp_factor * oxygen + p0, 0)

/// The radiation loss at the end of every step.
/proc/pp_sm_after_loss(p)
	return p - (p / PP_SM_DECAY) ** 3

/// Energy curve: a step in pure oxygen at 800 K adds T * ((400/700)^3 / 800) to the power, then loses (power/700)^3.
/datum/unit_test/dq_pp/sm_energy_curve_oxygen

/datum/unit_test/dq_pp/sm_energy_curve_oxygen/run_pp()
	var/list/room = pp_room(800, o2 = 200)
	var/obj/machinery/power/supermatter/SM = pp_sm(room[1])
	SM.power = 300
	pp_step(SM, PP_SM_STEP)
	var/expected = pp_sm_after_loss(pp_sm_gain(300, 800, 1))
	TEST_ASSERT(pp_close(SM.power, expected, 0.002), "power after one oxygen step: [SM.power], expected [expected]")
	TEST_ASSERT_EQUAL(SM.icon_state, "darkmatter_glow", "a crystal above 80% oxygen glows")

/// Nitrogen retards the reaction: oxygen fraction = (O2 - 0.15 N2) / total, and below 0.8 the equilibrium is 250.
/datum/unit_test/dq_pp/sm_energy_curve_nitrogen

/datum/unit_test/dq_pp/sm_energy_curve_nitrogen/run_pp()
	var/list/room = pp_room(1200, o2 = 60, n2 = 140)
	var/obj/machinery/power/supermatter/SM = pp_sm(room[1])
	SM.power = 100
	pp_step(SM, PP_SM_STEP)
	var/oxygen = (60 - 140 * 0.15) / 200
	var/expected = pp_sm_after_loss(pp_sm_gain(100, 1200, oxygen))
	TEST_ASSERT(pp_close(SM.power, expected, 0.002), "power after one nitrogen-retarded step: [SM.power], expected [expected]")
	TEST_ASSERT_EQUAL(SM.icon_state, "darkmatter", "a crystal below 80% oxygen does not glow")

/// Pure nitrogen: the oxygen fraction clamps at 0, so the step adds nothing and the crystal only decays.
/datum/unit_test/dq_pp/sm_energy_decays_in_nitrogen

/datum/unit_test/dq_pp/sm_energy_decays_in_nitrogen/run_pp()
	var/list/room = pp_room(300, o2 = 0, n2 = 200)
	var/obj/machinery/power/supermatter/SM = pp_sm(room[1])
	SM.power = 1400
	pp_step(SM, PP_SM_STEP)
	TEST_ASSERT(pp_close(SM.power, pp_sm_after_loss(1400), 0.001), "power after a nitrogen step: [SM.power], expected [pp_sm_after_loss(1400)]")
	TEST_ASSERT_EQUAL(SM.oxygen, 0, "pure nitrogen gives an oxygen fraction of 0")

/// What the step releases: a quarter of the room's gas is taken, phoron (device energy / 1500) and oxygen ((device energy + T - T0C) / 15000) are
/// added to it, it gains 10000 J per unit of device energy (device energy = power * 1.1), and it goes back to the room.
/datum/unit_test/dq_pp/sm_gas_release

/datum/unit_test/dq_pp/sm_gas_release/run_pp()
	var/list/room = pp_room(500, o2 = 200)
	var/turf/T = room[1]
	var/datum/gas_mixture/air = T.return_air()
	var/obj/machinery/power/supermatter/SM = pp_sm(T)
	SM.power = 500
	var/o2_before = pp_moles(air, /datum/gas/oxygen)
	var/e_before = pp_energy(air)
	pp_step(SM, PP_SM_STEP)
	var/device_energy = pp_sm_gain(500, 500, 1) * 1.1
	var/phoron = pp_moles(air, /datum/gas/plasma)
	TEST_ASSERT(pp_close(phoron, device_energy / 1500, 0.01), "phoron released: [phoron], expected [device_energy / 1500]")
	var/o2_added = pp_moles(air, /datum/gas/oxygen) - o2_before
	var/o2_expected = (device_energy + 500 - T0C) / 15000
	TEST_ASSERT(pp_close(o2_added, o2_expected, 0.02), "oxygen released: [o2_added], expected [o2_expected]")
	var/heat = pp_energy(air) - e_before
	var/thermal = 10000 * device_energy
	log_test("supermatter step at P=500, 500 K: device energy [device_energy], heat released [heat] J, expected [thermal] J (+ the released gas's own heat)")
	TEST_ASSERT(heat >= thermal * 0.99 && heat <= thermal * 1.05, "heat released: [heat] J, expected about [thermal] J")

/// Damage: a step adds (T - 5000) / 150, capped at (power / 300) * (explosion_point / 1000) * 3 and never below zero total; cool gas heals.
/datum/unit_test/dq_pp/sm_damage_curve

/datum/unit_test/dq_pp/sm_damage_curve/run_pp()
	// Hot: 8000 K wants +20 a step; at power 300 the cap is 3.
	var/list/room = pp_room(8000, o2 = 0, n2 = 200)
	var/obj/machinery/power/supermatter/SM = pp_sm(room[1])
	SM.power = 300
	SM.damage = 100
	pp_step(SM, PP_SM_STEP)
	TEST_ASSERT(pp_close(SM.damage, 103, 0.0001), "a hot step at power 300 is rate-limited to +3: damage [SM.damage]")
	TEST_ASSERT_EQUAL(SM.damage_archived, 100, "the step archives the damage it started from")
	// At power 3000 the cap is 30, so the full +20 lands.
	SM.power = 3000
	SM.damage = 100
	var/turf/T = room[1]
	heat_set(T.return_air(), 8000)
	pp_step(SM, PP_SM_STEP)
	TEST_ASSERT(pp_close(SM.damage, 120, 0.001), "a hot step at power 3000 adds (8000 - 5000) / 150 = 20: damage [SM.damage]")
	qdel(SM)

/datum/unit_test/dq_pp/sm_damage_heals_when_cool

/datum/unit_test/dq_pp/sm_damage_heals_when_cool/run_pp()
	var/list/room = pp_room(800, o2 = 0, n2 = 200)
	var/obj/machinery/power/supermatter/SM = pp_sm(room[1])
	SM.power = 0
	SM.damage = 50
	pp_step(SM, PP_SM_STEP)
	TEST_ASSERT(pp_close(SM.damage, 50 + (800 - PP_SM_CRITICAL) / 150, 0.001), "800 K heals (800 - 5000) / 150 a step: damage [SM.damage]")
	SM.damage = 10
	pp_step(SM, PP_SM_STEP)
	TEST_ASSERT_EQUAL(SM.damage, 0, "healing never takes the damage below zero")

/// No coolant (space): the damage grows by (power - 15) / 10 a step, unlimited.
/datum/unit_test/dq_pp/sm_damage_in_vacuum

/datum/unit_test/dq_pp/sm_damage_in_vacuum/run_pp()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no floor to open to space")
	var/turf/space/S = dq_atmos_test_open_to_space(pair[1])
	TEST_ASSERT_NOTNULL(S, "no space turf")
	var/obj/machinery/power/supermatter/SM = pp_sm(S)
	SM.power = 200
	pp_step(SM, PP_SM_STEP)
	TEST_ASSERT(pp_close(SM.damage, (200 - 15) / 10, 0.0001), "power 200 in space adds 18.5 damage a step: [SM.damage]")
	TEST_ASSERT(pp_close(SM.power, pp_sm_after_loss(200), 0.0001), "and the power only decays: [SM.power]")
	SM.power = 10
	SM.damage = 0
	pp_step(SM, PP_SM_STEP)
	TEST_ASSERT_EQUAL(SM.damage, 0, "below power 15 space does no damage")

/// Integrity is 100 - damage / explosion_point * 100, rounded, never below 0; the status bands follow it.
/datum/unit_test/dq_pp/sm_integrity_and_status

/datum/unit_test/dq_pp/sm_integrity_and_status/run_pp()
	var/list/room = pp_room(300, o2 = 0, n2 = 200)
	var/obj/machinery/power/supermatter/SM = pp_sm(room[1])
	TEST_ASSERT_EQUAL(SM.explosion_point, 1000, "a crystal delaminates past 1000 damage")
	TEST_ASSERT_EQUAL(SM.warning_point, 100, "it warns past 100")
	TEST_ASSERT_EQUAL(SM.emergency_point, 500, "it calls an emergency past 500")
	SM.damage = 0
	TEST_ASSERT_EQUAL(SM.get_integrity(), 100, "whole")
	TEST_ASSERT_EQUAL(SM.get_status(), SUPERMATTER_INACTIVE, "whole and unpowered is inactive")
	SM.power = 6
	TEST_ASSERT_EQUAL(SM.get_status(), SUPERMATTER_NORMAL, "above power 5 is normal")
	SM.damage = 250
	TEST_ASSERT_EQUAL(SM.get_integrity(), 75, "250 damage is 75%")
	SM.damage = 254
	TEST_ASSERT_EQUAL(SM.get_integrity(), 74, "integrity is floored: 254 damage is 74%")
	TEST_ASSERT_EQUAL(SM.get_status(), SUPERMATTER_WARNING, "under 100% integrity warns")
	SM.damage = 501
	TEST_ASSERT_EQUAL(SM.get_status(), SUPERMATTER_DANGER, "under 50% is danger")
	SM.damage = 751
	TEST_ASSERT_EQUAL(SM.get_status(), SUPERMATTER_EMERGENCY, "under 25% is an emergency")
	SM.damage = 2000
	TEST_ASSERT_EQUAL(SM.get_integrity(), 0, "integrity never goes below 0")
	SM.damage = 0
	var/turf/T = room[1]
	heat_set(T.return_air(), 4100)
	TEST_ASSERT_EQUAL(SM.get_status(), SUPERMATTER_NOTIFY, "air above 80% of 5000 K notifies")
	heat_set(T.return_air(), 5100)
	TEST_ASSERT_EQUAL(SM.get_status(), SUPERMATTER_WARNING, "air above 5000 K warns")
	var/obj/machinery/power/supermatter/shard/shard = pp_sm(room[2], /obj/machinery/power/supermatter/shard)
	TEST_ASSERT_EQUAL(shard.explosion_point, 600, "a shard delaminates past 600")
	TEST_ASSERT_EQUAL(shard.warning_point, 50, "a shard warns past 50")
	TEST_ASSERT_EQUAL(shard.emergency_point, 400, "a shard calls an emergency past 400")
	shard.damage = 300
	TEST_ASSERT_EQUAL(shard.get_integrity(), 50, "300 damage is half a shard")

/// The warning light: range 4 whole, 5 past the warning point, 7 past the emergency point.
/datum/unit_test/dq_pp/sm_warning_light

/datum/unit_test/dq_pp/sm_warning_light/run_pp()
	var/list/room = pp_room(300, o2 = 0, n2 = 200)
	var/obj/machinery/power/supermatter/SM = pp_sm(room[1])
	SM.damage = 150
	SM.safe_warned = TRUE
	pp_step(SM, PP_SM_STEP)
	TEST_ASSERT_EQUAL(SM.light_range, 5, "past the warning point the light is range 5")
	SM.damage = 600
	pp_step(SM, PP_SM_STEP)
	TEST_ASSERT_EQUAL(SM.light_range, 7, "past the emergency point the light is range 7")
	SM.damage = 0
	pp_step(SM, PP_SM_STEP)
	TEST_ASSERT_EQUAL(SM.light_range, 4, "a whole crystal's light is range 4")

/// Delamination: past the explosion point a step starts the countdown (on a station level: 30 s of causality field, then the explosion; off one:
/// at once). The explosion is the pull: grav_pulling and exploded set, anchored.
/datum/unit_test/dq_pp/sm_delamination

/datum/unit_test/dq_pp/sm_delamination/run_pp()
	var/list/room = pp_room(300, o2 = 0, n2 = 200)
	var/obj/machinery/power/supermatter/SM = pp_sm(room[1])
	SM.damage = SM.explosion_point - 1
	pp_step(SM, PP_SM_STEP)
	TEST_ASSERT(!SM.final_countdown && !SM.exploded && !SM.causalitywarn, "at the explosion point a crystal holds")
	SM.damage = SM.explosion_point + 1000 // the 300 K room heals 31 a step while the field holds
	pp_step(SM, PP_SM_STEP)
	TEST_ASSERT(SM.causalitywarn, "past the explosion point the causality warning is raised")
	if(SM.z in using_map.station_levels)
		TEST_ASSERT(SM.final_countdown, "on a station level the causality field holds it")
		TEST_ASSERT(!SM.exploded, "and it has not exploded yet")
		var/waited = 0
		while(!SM.exploded && waited < 60)
			test_time(1 SECOND)
			waited++
			if(waited % 10 == 1)
				log_test("countdown [waited] s: final_countdown [SM.final_countdown] damage [SM.damage] exploded [SM.exploded]")
		log_test("supermatter causality field held [waited] s")
		TEST_ASSERT(waited >= 30 && waited <= 33, "the field holds for 30 seconds, then it explodes: exploded after [waited] s")
	else
		TEST_ASSERT(SM.exploded, "off a station level it explodes at once")
	TEST_ASSERT(SM.grav_pulling, "an exploding crystal pulls")
	TEST_ASSERT(SM.anchored, "an exploding crystal is anchored")
	TEST_ASSERT_EQUAL(SM.get_status(), SUPERMATTER_DELAMINATING, "and reports delaminating")
	// Never let the blast itself run in the test world.
	SM.delamination_delete = TRUE
	qdel(SM)

/// The causality field is a last chance: bringing the damage back under the explosion point during the countdown disengages it.
/datum/unit_test/dq_pp/sm_countdown_abort

/datum/unit_test/dq_pp/sm_countdown_abort/run_pp()
	var/list/room = pp_room(300, o2 = 0, n2 = 200)
	var/obj/machinery/power/supermatter/SM = pp_sm(room[1])
	if(!(SM.z in using_map.station_levels))
		log_test("the test level is not a station level: the countdown abort is not reachable here")
		return
	SM.damage = SM.explosion_point + 10
	pp_step(SM, PP_SM_STEP)
	TEST_ASSERT(SM.final_countdown, "the countdown started")
	test_time(5 SECONDS)
	SM.damage = SM.explosion_point - 10
	test_time(2 SECONDS)
	TEST_ASSERT(!SM.final_countdown, "the field disengaged")
	test_time(30 SECONDS)
	TEST_ASSERT(!SM.exploded, "and it never exploded")

/// Emitter shots charge it: a beam adds damage * 2 * 0.05 power; any other projectile adds damage * 2 damage.
/datum/unit_test/dq_pp/sm_projectiles

/datum/unit_test/dq_pp/sm_projectiles/run_pp()
	var/list/room = pp_room(300, o2 = 0, n2 = 200)
	var/obj/machinery/power/supermatter/SM = pp_sm(room[1])
	var/obj/item/projectile/beam/emitter/beam = allocate(/obj/item/projectile/beam/emitter, room[2])
	var/beam_damage = beam.get_structure_damage()
	SM.bullet_act(beam)
	TEST_ASSERT(pp_close(SM.power, beam_damage * 2 * 0.05, 0.0001), "an emitter beam of [beam_damage] adds [beam_damage * 0.1] power: [SM.power]")
	TEST_ASSERT_EQUAL(SM.damage, 0, "a beam does no damage")
	var/obj/item/projectile/bullet/bullet = allocate(/obj/item/projectile/bullet, room[2])
	var/bullet_damage = bullet.get_structure_damage()
	SM.bullet_act(bullet)
	TEST_ASSERT(pp_close(SM.damage, bullet_damage * 2, 0.0001), "a bullet of [bullet_damage] adds [bullet_damage * 2] damage: [SM.damage]")

/// Whatever touches it is consumed: an object adds 200 power.
/datum/unit_test/dq_pp/sm_consumes

/datum/unit_test/dq_pp/sm_consumes/run_pp()
	var/list/room = pp_room(300, o2 = 0, n2 = 200)
	var/obj/machinery/power/supermatter/SM = pp_sm(room[1])
	var/obj/item/stack/rods/rod = new(room[2])
	SM.Bumped(rod)
	TEST_ASSERT(QDELETED(rod), "the object is gone")
	TEST_ASSERT_EQUAL(SM.power, 200, "and the crystal gained 200 power")

/// The crystal steps on its own every 2 seconds while it sits on a turf: in space at power 200, 10 seconds is 5 steps of damage.
/datum/unit_test/dq_pp/sm_cadence

/datum/unit_test/dq_pp/sm_cadence/run_pp()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no floor to open to space")
	var/turf/space/S = dq_atmos_test_open_to_space(pair[1])
	TEST_ASSERT_NOTNULL(S, "no space turf")
	var/obj/machinery/power/supermatter/SM = pp_sm(S)
	SM.power = 15 // no space damage at 15, so the steps only show in the decay
	test_time(1 SECOND)
	SM.power = 1000
	var/p = 1000
	test_time(10 SECONDS)
	var/steps = 0
	while(steps < 10 && !pp_close(SM.power, p, 0.0001))
		p = pp_sm_after_loss(p)
		steps++
	log_test("supermatter in space: [steps] steps in 10 s")
	TEST_ASSERT(steps >= 4 && steps <= 6, "a crystal steps every 2 seconds: [steps] steps in 10 s (power [SM.power])")

#undef PP_SM_STEP
#undef PP_SM_DECAY
#undef PP_SM_CRITICAL
