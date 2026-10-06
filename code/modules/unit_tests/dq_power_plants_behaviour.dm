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
	return D.periodic_step()

/// Locks or unlocks a machine's controls: its lock() capability's key, or the legacy `locked` var.
/proc/pp_set_lock(obj/machinery/M, value)
	if(cap_of(M, CAP_LOCK, null))
		key_set(M, LOCK_LOCKED, value)
	else
		M.set_locked(value)

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
	rod.bump_into(SM)
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

// ============================================================================================ the singularity and its containment

#define PP_SING_STEP "singularity_frame"
#define PP_FG_STEP "field_step"
#define PP_EMITTER_STEP "emitter_step"
#define PP_GEN_STEP "collapse_check"

/// A straight run of `n` clear floor turfs, at least 10 tiles from every map edge (a field generator looks 9 tiles out each way).
/datum/unit_test/dq_pp/proc/pp_run(n)
	dq_atmos_test_restore_walls()
	for(var/turf/simulated/floor/cand in world)
		if(!cand.air || cand.blocks_air || cand.x < 11 || cand.y < 11 || cand.x > world.maxx - 10 - n || cand.y > world.maxy - 10 - n)
			continue
		for(var/direction in GLOB.cardinal)
			var/list/run = list(cand)
			var/turf/cur = cand
			for(var/i in 2 to n)
				cur = get_step(cur, direction)
				if(!istype(cur, /turf/simulated/floor) || cur.density || length(cur.contents))
					break
				run += cur
			if(length(run) == n && !length(cand.contents))
				return run
	TEST_FAIL("no clear run of [n] floors")

/// The direction from the first turf of a run to the second.
/proc/pp_run_dir(list/run)
	return get_dir(run[1], run[2])

/// A singularity of `energy` at T that does not wander on its own (move_self 0) unless a test moves it.
/datum/unit_test/dq_pp/proc/pp_singularity(turf/T, energy = 100)
	var/obj/singularity/S = allocate(/obj/singularity, T, energy)
	S.move_self = 0
	return S

/// Size thresholds: 1-199 is stage one, 200 two, 500 three, 1000 four, 2000 five, 50000 the super singularity.
/datum/unit_test/dq_pp/sing_size_thresholds

/datum/unit_test/dq_pp/sing_size_thresholds/run_pp()
	var/list/run = pp_run(1)
	var/obj/singularity/S = pp_singularity(run[1])
	var/list/expected = list("1" = STAGE_ONE, "199" = STAGE_ONE, "200" = STAGE_TWO, "499" = STAGE_TWO, "500" = STAGE_THREE, "999" = STAGE_THREE,
		"1000" = STAGE_FOUR, "1999" = STAGE_FOUR, "2000" = STAGE_FIVE, "49999" = STAGE_FIVE, "50000" = STAGE_SUPER)
	for(var/e in expected)
		S.energy = text2num(e)
		S.current_size = STAGE_SUPER // never expand during the sweep
		S.check_energy()
		TEST_ASSERT_EQUAL(S.allowed_size, expected[e], "energy [e] allows size [expected[e]]")
	S.current_size = STAGE_ONE
	S.energy = 300
	S.check_energy()
	TEST_ASSERT_EQUAL(S.current_size, STAGE_TWO, "energy 300 grows a stage-one singularity to stage two")
	TEST_ASSERT_EQUAL(S.grav_pull, 6, "a stage-two singularity pulls 6 tiles")
	TEST_ASSERT_EQUAL(S.consume_range, 1, "and eats 1 tile out")
	TEST_ASSERT_EQUAL(S.dissipate_strength, 5, "and loses 5 energy a dissipation")
	S.energy = 100
	S.check_energy()
	TEST_ASSERT_EQUAL(S.current_size, STAGE_ONE, "energy 100 shrinks it back to stage one")

/// Dissipation: a stage-one singularity loses 1 energy every 11th dissipation (its track counts to 10 first); one that does not dissipate keeps it.
/datum/unit_test/dq_pp/sing_dissipation

/datum/unit_test/dq_pp/sing_dissipation/run_pp()
	var/list/run = pp_run(1)
	var/obj/singularity/S = pp_singularity(run[1], 100)
	for(var/i in 1 to 10)
		S.dissipate()
	TEST_ASSERT_EQUAL(S.energy, 100, "ten dissipations lose nothing yet")
	S.dissipate()
	TEST_ASSERT_EQUAL(S.energy, 99, "the eleventh loses 1")
	S.dissipate = 0
	for(var/i in 1 to 22)
		S.dissipate()
	TEST_ASSERT_EQUAL(S.energy, 99, "a singularity that does not dissipate keeps its energy")

/// A step eats what lies under it (the floor: +2), dissipates and checks its size; with no energy left it collapses.
/datum/unit_test/dq_pp/sing_step_and_collapse

/datum/unit_test/dq_pp/sing_step_and_collapse/run_pp()
	var/list/run = pp_run(1)
	var/obj/singularity/S = pp_singularity(run[1], 100)
	var/list/energies = list()
	for(var/i in 1 to 11)
		pp_step(S, PP_SING_STEP)
		energies += S.energy
	log_test("singularity energies over 11 steps: [jointext(energies, ",")]")
	TEST_ASSERT_EQUAL(S.dissipate_track, 0, "the eleventh step dissipated")
	TEST_ASSERT_EQUAL(energies[1], 102, "the first step ate the floor under it (+2)")
	TEST_ASSERT_EQUAL(energies[11], 101, "the eleventh lost 1 to dissipation")
	S.energy = 0
	S.check_energy()
	TEST_ASSERT(QDELETED(S), "a singularity at 0 energy collapses")

/// Containment: a turf holding a containment field or an ACTIVE field generator stops it; an inactive generator does not.
/datum/unit_test/dq_pp/sing_containment_turfs

/datum/unit_test/dq_pp/sing_containment_turfs/run_pp()
	var/list/run = pp_run(4)
	var/obj/singularity/S = pp_singularity(run[1])
	TEST_ASSERT(S.can_move(run[2]), "an empty floor does not stop it")
	var/obj/machinery/containment_field/F = allocate(/obj/machinery/containment_field, run[2])
	TEST_ASSERT(!S.can_move(run[2]), "a containment field stops it")
	qdel(F)
	var/obj/machinery/field_generator/G = allocate(/obj/machinery/field_generator, run[3])
	TEST_ASSERT(S.can_move(run[3]), "an inactive field generator does not")
	G.set_active(1)
	TEST_ASSERT(!S.can_move(run[3]), "an active field generator does")
	G.set_active(0)

/// Escape: a contained singularity's step toward a field is refused (it remembers the direction); one that does not move itself never moves;
/// at stage five nothing stops it.
/datum/unit_test/dq_pp/sing_escape_conditions

/datum/unit_test/dq_pp/sing_escape_conditions/run_pp()
	var/list/run = pp_run(6)
	var/dir = pp_run_dir(run)
	var/obj/singularity/S = pp_singularity(run[1], 100)
	S.move_self = 1
	allocate(/obj/machinery/containment_field, run[2])
	TEST_ASSERT(!S.move(dir), "a stage-one singularity does not step into a field")
	TEST_ASSERT_EQUAL(S.loc, run[1], "it stayed put")
	TEST_ASSERT_EQUAL(S.last_failed_movement, dir, "and remembers the blocked direction")
	S.move_self = 0
	TEST_ASSERT(!S.move(turn(dir, 180)), "a singularity that does not move itself never moves")
	TEST_ASSERT_EQUAL(S.loc, run[1], "it stayed put")
	qdel(S)
	var/obj/singularity/big = pp_singularity(run[3], 100)
	big.move_self = 1
	big.current_size = STAGE_FIVE
	TEST_ASSERT(big.move(turn(dir, 180)), "a stage-five singularity ignores containment: it never checks the turfs it steps to")
	qdel(big)

/// A loaded, active collector.
/datum/unit_test/dq_pp/proc/pp_collector(turf/T)
	var/obj/machinery/power/rad_collector/C = allocate(/obj/machinery/power/rad_collector, T)
	C.set_anchored(TRUE)
	var/obj/item/tank/phoron/tank = allocate(/obj/item/tank/phoron, T)
	TEST_ASSERT(move_into(C, nameof(C.P), tank), "the tank went in")
	C.toggle_power()
	TEST_ASSERT(C.active, "the collector is on")
	return C

/// What it feeds the collectors: every collector within 15 tiles receives a pulse of its energy (power = phoron moles * energy * 20).
/datum/unit_test/dq_pp/sing_pulse_feeds_collectors

/datum/unit_test/dq_pp/sing_pulse_feeds_collectors/run_pp()
	var/list/run = pp_run(3)
	var/obj/singularity/S = pp_singularity(run[1], 300)
	var/obj/machinery/power/rad_collector/C = pp_collector(run[3])
	var/moles = C.P.air_contents.get_moles(/datum/gas/plasma)
	S.pulse()
	TEST_ASSERT(pp_close(C.last_power_new, moles * 300 * 20, 0.0001), "a 300-energy pulse makes [moles * 300 * 20] W: [C.last_power_new]")

/// A collector makes phoron moles * pulse strength * 20 W per pulse, and nothing switched off.
/datum/unit_test/dq_pp/collector_output

/datum/unit_test/dq_pp/collector_output/run_pp()
	var/list/run = pp_run(1)
	var/obj/machinery/power/rad_collector/C = pp_collector(run[1])
	var/moles = C.P.air_contents.get_moles(/datum/gas/plasma)
	C.receive_pulse(170)
	TEST_ASSERT(pp_close(C.last_power_new, moles * 170 * 20, 0.0001), "170 rads make moles * 3400 W: [C.last_power_new]")
	C.toggle_power()
	C.last_power_new = 0
	C.receive_pulse(170)
	TEST_ASSERT_EQUAL(C.last_power_new, 0, "an inactive collector makes nothing")

/// The singularity generator becomes a singularity once particles have given it 200 energy, and not before.
/datum/unit_test/dq_pp/sing_generator_threshold

/datum/unit_test/dq_pp/sing_generator_threshold/run_pp()
	var/list/run = pp_run(1)
	var/obj/machinery/the_singularitygen/G = allocate(/obj/machinery/the_singularitygen, run[1])
	G.energy = 199
	pp_step(G, PP_GEN_STEP)
	TEST_ASSERT(!QDELETED(G), "199 energy is not enough")
	TEST_ASSERT(!locate_on(run[1], /obj/singularity), "and no singularity formed")
	G.energy = 200
	pp_step(G, PP_GEN_STEP)
	TEST_ASSERT(QDELETED(G), "200 energy collapses the generator")
	var/obj/singularity/S = locate_on(run[1], /obj/singularity)
	TEST_ASSERT_NOTNULL(S, "into a singularity")
	TEST_ASSERT_EQUAL(S.energy, 50, "that starts at 50 energy")
	qdel(S)

/// Particles: a weak particle gives 5 energy, a normal one 10, a strong one 15, a powerful one 50.
/datum/unit_test/dq_pp/particle_energies

/datum/unit_test/dq_pp/particle_energies/run_pp()
	var/list/run = pp_run(1)
	var/obj/machinery/the_singularitygen/G = allocate(/obj/machinery/the_singularitygen, run[1])
	var/list/expected = list(/obj/effect/accelerated_particle/weak = 5, /obj/effect/accelerated_particle = 10,
		/obj/effect/accelerated_particle/strong = 15, /obj/effect/accelerated_particle/powerful = 50)
	for(var/path in expected)
		var/obj/effect/accelerated_particle/P = new path(null)
		var/before = G.energy
		P.Bump(G)
		TEST_ASSERT_EQUAL(G.energy - before, expected[path], "[path] gives [expected[path]] energy")
		qdel(P)
	TEST_ASSERT(!QDELETED(G), "80 energy is not a singularity yet")

/// The accelerator's emitters fire at most once per 5 s.
/datum/unit_test/dq_pp/pa_emitter_rate

/datum/unit_test/dq_pp/pa_emitter_rate/run_pp()
	var/list/run = pp_run(1)
	var/obj/structure/particle_accelerator/particle_emitter/center/E = allocate(/obj/structure/particle_accelerator/particle_emitter/center, run[1])
	TEST_ASSERT_EQUAL(E.fire_delay, 5 SECONDS, "the emitters' delay is 5 s")
	TEST_ASSERT(E.emit_particle(2), "a ready emitter fires")
	TEST_ASSERT(!E.emit_particle(2), "and not again within its delay")
	TEST_ASSERT_EQUAL(COOLDOWN_TIMELEFT(E, shot_cooldown), 5 SECONDS, "which is 5 s")
	COOLDOWN_RESET(E, shot_cooldown)
	TEST_ASSERT(E.emit_particle(0), "after it, it fires again")
	for(var/obj/effect/accelerated_particle/P in range(2, E))
		qdel(P)

// ---- field generators ----

/// A welded generator with `power` in store.
/datum/unit_test/dq_pp/proc/pp_field_gen(turf/T, power = 100000)
	var/obj/machinery/field_generator/G = allocate(/obj/machinery/field_generator, T)
	G.set_state(2)
	G.set_anchored(TRUE)
	G.power = power
	return G

/// Power draw: a running generator pays half of 5500 W, plus 5500 per linked generator and 2000 per field, every step; its store is capped at
/// 250000 first.
/datum/unit_test/dq_pp/fg_power_draw

/datum/unit_test/dq_pp/fg_power_draw/run_pp()
	var/list/run = pp_run(1)
	var/obj/machinery/field_generator/G = pp_field_gen(run[1], 100000)
	G.set_active(2)
	pp_step(G, PP_FG_STEP)
	TEST_ASSERT_EQUAL(G.power, 100000 - 2750, "a lone generator pays 2750 a step")
	TEST_ASSERT_EQUAL(G.active, 2, "and stays up")
	G.power = 300000
	pp_step(G, PP_FG_STEP)
	TEST_ASSERT_EQUAL(G.power, 250000 - 2750, "its store is capped at 250000 before it pays")
	G.set_active(0)

/// Containment failure by power: a generator that cannot pay shuts down (its fields fall) and empties.
/datum/unit_test/dq_pp/fg_power_failure

/datum/unit_test/dq_pp/fg_power_failure/run_pp()
	var/list/run = pp_run(1)
	var/obj/machinery/field_generator/G = pp_field_gen(run[1], 1000)
	G.set_active(2)
	pp_step(G, PP_FG_STEP)
	TEST_ASSERT_EQUAL(G.active, 0, "a generator that cannot pay its 2750 shuts down")
	TEST_ASSERT_EQUAL(G.power, 0, "and is left empty")

/// Two generators 4 tiles apart raise 3 field tiles between them after the 10 s warm-up, a linked generator with 3 fields pays
/// (5500 * 2 + 2000 * 3) / 2 a step, and the fields fall when one is switched off.
/datum/unit_test/dq_pp/fg_fields_and_warmup

/datum/unit_test/dq_pp/fg_fields_and_warmup/run_pp()
	var/list/run = pp_run(5)
	var/obj/machinery/field_generator/A = pp_field_gen(run[1])
	var/obj/machinery/field_generator/B = pp_field_gen(run[5])
	A.turn_on()
	B.turn_on()
	test_time(9 SECONDS)
	TEST_ASSERT(A.active != 2, "the warm-up takes 10 s (two more stages, 5 s each)")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(A.active, 2, "after 10 s the generator is up")
	TEST_ASSERT_EQUAL(B.active, 2, "both are")
	test_time(1 SECOND)
	for(var/i in 2 to 4)
		TEST_ASSERT_NOTNULL(locate_on(run[i], /obj/machinery/containment_field), "a field stands on tile [i]")
	TEST_ASSERT_EQUAL(length(A.fields), 3, "A powers 3 fields")
	TEST_ASSERT(B in A.connected_gens, "and is linked to B")
	A.power = 100000
	pp_step(A, PP_FG_STEP)
	var/draw = round((5500 * 2 + 2000 * 3) / 2)
	TEST_ASSERT_EQUAL(A.power, 100000 - draw, "a linked generator with 3 fields pays [draw] a step: [A.power]")
	A.turn_off()
	test_time(1 SECOND)
	for(var/i in 2 to 4)
		TEST_ASSERT(!locate_on(run[i], /obj/machinery/containment_field), "the field on tile [i] fell")
	TEST_ASSERT(!length(A.connected_gens), "and the generators are unlinked")
	B.turn_off()
	test_time(1 SECOND)

/// An emitter beam charges a field generator: damage * EMITTER_DAMAGE_POWER_TRANSFER.
/datum/unit_test/dq_pp/fg_beam_charges

/datum/unit_test/dq_pp/fg_beam_charges/run_pp()
	var/list/run = pp_run(2)
	var/obj/machinery/field_generator/G = pp_field_gen(run[1], 0)
	var/obj/item/projectile/beam/emitter/beam = allocate(/obj/item/projectile/beam/emitter, run[2])
	beam.damage = 100
	G.bullet_act(beam)
	TEST_ASSERT_EQUAL(G.power, 100 * EMITTER_DAMAGE_POWER_TRANSFER, "a 100-damage beam gives [100 * EMITTER_DAMAGE_POWER_TRANSFER]")

/// The containment field: a dense non-living thing that crosses it is destroyed, a loose item is not; a field whose generators are gone falls when
/// it would shock.
/datum/unit_test/dq_pp/containment_field_effects

/datum/unit_test/dq_pp/containment_field_effects/run_pp()
	var/list/run = pp_run(3)
	var/obj/machinery/field_generator/A = pp_field_gen(run[1])
	var/obj/machinery/field_generator/B = pp_field_gen(run[3])
	var/obj/machinery/containment_field/F = allocate(/obj/machinery/containment_field, run[2])
	F.set_master(A, B)
	var/obj/structure/closet/crate = allocate(/obj/structure/closet, run[2])
	F.Crossed(crate)
	TEST_ASSERT(QDELETED(crate), "a dense object crossing the field is destroyed")
	var/obj/item/stack/rods/rod = allocate(/obj/item/stack/rods, run[2])
	F.Crossed(rod)
	TEST_ASSERT(!QDELETED(rod), "a loose item is not")
	qdel(B)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run[1])
	F.shock(H)
	TEST_ASSERT(QDELETED(F), "a field without both generators falls when it would shock")

// ---- emitters ----

/// A clear space lane to fire into.
/datum/unit_test/dq_pp/proc/pp_lane()
	for(var/turf/space/candidate in world)
		if(candidate.x > 2 && candidate.y > 2 && candidate.y < world.maxy - 12 && istype(get_step(candidate, NORTH), /turf/space))
			return candidate
	TEST_FAIL("no clear firing lane")

/// A welded emitter on test grid `net`.
/datum/unit_test/dq_pp/proc/pp_emitter(turf/T, dir, net)
	var/obj/machinery/power/emitter/E = allocate(/obj/machinery/power/emitter, T)
	E.set_dir(dir)
	E.set_anchored(TRUE)
	E.set_state(2)
	power_test_join(net, E)
	return E

/// Emitter firing: one shot is 30 kW over the 6.4 s mean burst, a third of it: 64000 J of beam; a burst is four shots (the burst delay is shorter
/// than a step, so one a step), then a 2-10 s pause; an emitter that is no longer welded switches off.
/datum/unit_test/dq_pp/emitter_firing

/datum/unit_test/dq_pp/emitter_firing/run_pp()
	var/turf/lane = pp_lane()
	var/net = power_test_grid(10000000)
	var/obj/machinery/power/emitter/E = pp_emitter(lane, NORTH, net)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, get_step(lane, SOUTH))
	E.activate(H)
	TEST_ASSERT_EQUAL(E.active, 1, "a welded, wired emitter switches on")
	E.material_last_charge = world.time - 10 SECONDS
	E.charge_emitter()
	E.material_stored_energy = 1e7
	var/shot = 30000 * 6.4 / 3
	var/before = E.material_beam_joules
	COOLDOWN_RESET(E, shot_cooldown)
	pp_step(E, PP_EMITTER_STEP)
	TEST_ASSERT(pp_close(E.material_beam_joules - before, shot, 0.0001), "one shot is [shot] J: [E.material_beam_joules - before]")
	TEST_ASSERT_EQUAL(E.shot_number, 1, "the burst counts its shots")
	TEST_ASSERT_EQUAL(E.fire_delay, E.burst_delay, "the next shot of the burst waits the burst delay")
	pp_step(E, PP_EMITTER_STEP)
	TEST_ASSERT(pp_close(E.material_beam_joules - before, shot, 0.0001), "and not at once")
	for(var/i in 1 to 3)
		COOLDOWN_RESET(E, shot_cooldown)
		pp_step(E, PP_EMITTER_STEP)
	TEST_ASSERT_EQUAL(E.shot_number, 0, "the fourth shot ends the burst")
	TEST_ASSERT(E.fire_delay >= E.min_burst_delay && E.fire_delay <= E.max_burst_delay, "and the pause is 2-10 s: [E.fire_delay]")
	TEST_ASSERT(pp_close(E.material_beam_joules - before, shot * 4, 0.0001), "four shots: [E.material_beam_joules - before]")
	E.set_state(1)
	pp_step(E, PP_EMITTER_STEP)
	TEST_ASSERT_EQUAL(E.active, 0, "an emitter that is no longer welded switches off")
	for(var/obj/item/projectile/P in range(12, lane))
		qdel(P)
	power_test_drop_grid(net)

/// The emitter's switch: unwelded it refuses to switch on; locked it does not switch; unlocked it switches on and off.
/datum/unit_test/dq_pp/emitter_controls

/datum/unit_test/dq_pp/emitter_controls/run_pp()
	var/list/run = pp_run(1)
	var/net = power_test_grid(10000000)
	var/obj/machinery/power/emitter/E = allocate(/obj/machinery/power/emitter, run[1])
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run[1])
	E.activate(H)
	TEST_ASSERT_EQUAL(E.active, 0, "an unwelded emitter does not switch on")
	E.set_anchored(TRUE)
	E.set_state(2)
	power_test_join(net, E)
	pp_set_lock(E, TRUE)
	E.activate(H)
	TEST_ASSERT_EQUAL(E.active, 0, "a locked emitter does not switch on")
	pp_set_lock(E, FALSE)
	E.activate(H)
	TEST_ASSERT_EQUAL(E.active, 1, "an unlocked one does")
	E.activate(H)
	TEST_ASSERT_EQUAL(E.active, 0, "and off again")
	power_test_drop_grid(net)

#undef PP_SING_STEP
#undef PP_FG_STEP
#undef PP_EMITTER_STEP
#undef PP_GEN_STEP

// ============================================================================================ the tesla coils

/// Coil curves with the default (rating 1) capacitor: a plain coil keeps half (power_loss 2) at x1; a relay passes 0.9; a prism splits into 2
/// bolts; an amplifier gains 7.5%; a recaster reaches 6 tiles; a collector takes it all at x2 and does not arc; every coil zaps every 1 s.
/datum/unit_test/dq_pp/tesla_coil_curves

/datum/unit_test/dq_pp/tesla_coil_curves/run_pp()
	var/list/run = pp_run(1)
	var/obj/machinery/power/tesla_coil/C = allocate(/obj/machinery/power/tesla_coil, run[1])
	TEST_ASSERT_EQUAL(C.power_loss, 2, "a coil keeps half")
	TEST_ASSERT_EQUAL(C.input_power_multiplier, 1, "at x1 with a basic capacitor")
	TEST_ASSERT_EQUAL(C.zap_cooldown, 10, "and zaps every second")
	TEST_ASSERT_EQUAL(C.zap_range, 5, "5 tiles out")
	var/obj/machinery/power/tesla_coil/relay/R = allocate(/obj/machinery/power/tesla_coil/relay, run[1])
	TEST_ASSERT(pp_close(R.relay_efficiency, 0.9, 0.0001), "a relay passes 90%: [R.relay_efficiency]")
	TEST_ASSERT_EQUAL(R.power_loss, 1, "and loses nothing itself")
	var/obj/machinery/power/tesla_coil/splitter/S = allocate(/obj/machinery/power/tesla_coil/splitter, run[1])
	TEST_ASSERT_EQUAL(S.split_count, 1, "a prism adds one bolt")
	var/obj/machinery/power/tesla_coil/amplifier/A = allocate(/obj/machinery/power/tesla_coil/amplifier, run[1])
	TEST_ASSERT(pp_close(A.amp_eff, 1.075, 0.0001), "an amplifier gains 7.5%: [A.amp_eff]")
	var/obj/machinery/power/tesla_coil/recaster/RC = allocate(/obj/machinery/power/tesla_coil/recaster, run[1])
	TEST_ASSERT_EQUAL(RC.zap_range, 6, "a recaster reaches 6 tiles")
	var/obj/machinery/power/tesla_coil/collector/CO = allocate(/obj/machinery/power/tesla_coil/collector, run[1])
	TEST_ASSERT_EQUAL(CO.input_power_multiplier, 2, "a collector takes it all at x2")
	TEST_ASSERT_EQUAL(CO.zap_range, 0, "and does not arc")
	TEST_ASSERT_EQUAL(CO.power_loss, 1, "and loses nothing")

// ============================================================================================ fusion

#define PP_FIELD_STEP "field_react"
#define PP_INJECTOR_STEP "inject_step"
#define PP_TRAP_STEP "trap_step"

/// A core with its field up at `strength`, on a clear floor.
/datum/unit_test/dq_pp/proc/pp_fusion_field(turf/T, strength = 1)
	var/obj/machinery/power/fusion_core/core = allocate(/obj/machinery/power/fusion_core, T)
	core.field_strength = strength
	core.Startup()
	TEST_ASSERT_NOTNULL(core.owned_field, "the core raised its field")
	return core.owned_field

/// The field's size follows the core's strength: up to 50 is 1, 200 is 3, 500 is 5, above is 7; the strength is clamped to 1..1000 and the
/// core draws 5 W per unit of it.
/datum/unit_test/dq_pp/fusion_field_strength

/datum/unit_test/dq_pp/fusion_field_strength/run_pp()
	var/list/run = pp_run(1)
	var/obj/effect/fusion_em_field/F = pp_fusion_field(run[1])
	var/obj/machinery/power/fusion_core/core = F.owned_core
	var/list/expected = list("1" = 1, "50" = 1, "51" = 3, "200" = 3, "201" = 5, "500" = 5, "501" = 7, "1000" = 7)
	for(var/strength in expected)
		F.ChangeFieldStrength(text2num(strength))
		TEST_ASSERT_EQUAL(F.size, expected[strength], "strength [strength] makes a field of size [expected[strength]]")
	core.set_strength(5000)
	TEST_ASSERT_EQUAL(core.field_strength, 1000, "the strength is capped at 1000")
	TEST_ASSERT_EQUAL(core.active_power_usage, 5000, "and draws 5 W a unit")
	core.set_strength(0)
	TEST_ASSERT_EQUAL(core.field_strength, 1, "and floored at 1")
	core.Shutdown()

/// Heating: 100 energy is 1 K of plasma; energy also steadies an unstable field (energy / 10000 off its instability).
/datum/unit_test/dq_pp/fusion_add_energy

/datum/unit_test/dq_pp/fusion_add_energy/run_pp()
	var/list/run = pp_run(1)
	var/obj/effect/fusion_em_field/F = pp_fusion_field(run[1])
	F.percent_unstable = 0.5
	F.AddEnergy(250, 3)
	TEST_ASSERT_EQUAL(F.plasma_temperature, 5, "3 K plus 250 energy's 2 K")
	TEST_ASSERT_EQUAL(F.energy, 50, "50 energy left over")
	TEST_ASSERT(pp_close(F.percent_unstable, 0.5 - 0.025, 0.0001), "250 energy steadies it by 0.025: [F.percent_unstable]")
	F.owned_core.Shutdown()

/// A field step with nothing to react: 1% of the plasma's heat is lost to radiation.
/datum/unit_test/dq_pp/fusion_field_decay

/datum/unit_test/dq_pp/fusion_field_decay/run_pp()
	var/list/run = pp_run(1)
	var/obj/effect/fusion_em_field/F = pp_fusion_field(run[1])
	F.plasma_temperature = 500
	F.radiation = 0
	pp_step(F, PP_FIELD_STEP)
	TEST_ASSERT(pp_close(F.plasma_temperature, 495, 0.0001), "500 K loses 1%: [F.plasma_temperature]")
	TEST_ASSERT(pp_close(F.radiation, 5, 0.0001), "to radiation: [F.radiation]")
	F.owned_core.Shutdown()

/// Instability: a step's tick instability adds tick * size / 10000 to the field's instability (a calm step's bleed rounds to nothing).
/datum/unit_test/dq_pp/fusion_instability

/datum/unit_test/dq_pp/fusion_instability/run_pp()
	var/list/run = pp_run(1)
	var/obj/effect/fusion_em_field/F = pp_fusion_field(run[1])
	F.tick_instability = 100
	F.check_instability()
	TEST_ASSERT(pp_close(F.percent_unstable, 0.01, 0.0001), "100 instability on a size-1 field is 1%: [F.percent_unstable]")
	TEST_ASSERT_EQUAL(F.tick_instability, 0, "and the tick's count is spent")
	F.check_instability()
	TEST_ASSERT(pp_close(F.percent_unstable, 0.01, 0.0001), "a calm step's bleed is rand(0.01, 0.03), which rounds to 0: it stays: [F.percent_unstable]")
	F.owned_core.Shutdown()

/// The reaction table (rates per unit reacted): D+D 1 in, 2 out; D+He3 1 in, 5 out; D+T 1 in, 1 out, He3 product, 0.5 instability; D+Li 2 in,
/// 0 out, 3 radiation, T product, 1 instability; O+O 10 in.
/datum/unit_test/dq_pp/fusion_reaction_rates

/datum/unit_test/dq_pp/fusion_reaction_rates/run_pp()
	var/datum/decl/fusion_reaction/R = get_fusion_reaction(REAGENT_ID_DEUTERIUM, REAGENT_ID_DEUTERIUM)
	TEST_ASSERT(R && R.energy_consumption == 1 && R.energy_production == 2, "D+D")
	R = get_fusion_reaction(REAGENT_ID_HELIUM3, REAGENT_ID_DEUTERIUM)
	TEST_ASSERT(R && R.energy_consumption == 1 && R.energy_production == 5, "D+He3 either way round")
	R = get_fusion_reaction(REAGENT_ID_DEUTERIUM, REAGENT_ID_SLIMEJELLY)
	TEST_ASSERT(R && R.energy_production == 1 && R.instability == 0.5 && R.products[REAGENT_ID_HELIUM3] == 1, "D+T")
	R = get_fusion_reaction(REAGENT_ID_DEUTERIUM, REAGENT_ID_LITHIUM)
	TEST_ASSERT(R && R.energy_consumption == 2 && R.radiation == 3 && R.instability == 1, "D+Li")
	R = get_fusion_reaction(REAGENT_ID_OXYGEN, REAGENT_ID_OXYGEN)
	TEST_ASSERT(R && R.energy_consumption == 10, "O+O")
	TEST_ASSERT_EQUAL(R.minimum_reaction_temperature, 100, "reactions need 100 K")

/// The fuel injector fires one particle per fuel in its rod a step, and burns fuel_usage (30) of each; it stops when it cannot work.
/datum/unit_test/dq_pp/fusion_injector_fuel_use

/datum/unit_test/dq_pp/fusion_injector_fuel_use/run_pp()
	var/list/run = pp_run(2)
	var/obj/machinery/fusion_fuel_injector/I = allocate(/obj/machinery/fusion_fuel_injector, run[1])
	var/area/room = get_area(run[1])
	var/area_required = room.requires_power
	room.requires_power = FALSE
	I.power_change()
	var/obj/item/fuel_assembly/rod = allocate(/obj/item/fuel_assembly, run[1])
	rod.rod_quantities = list(REAGENT_ID_DEUTERIUM = 3000000)
	TEST_ASSERT(move_into(I, nameof(I.cur_assembly), rod), "the rod went in")
	I.BeginInjecting()
	TEST_ASSERT(I.injecting, "it injects")
	pp_step(I, PP_INJECTOR_STEP)
	TEST_ASSERT_EQUAL(rod.rod_quantities[REAGENT_ID_DEUTERIUM], 3000000 - 30, "a step burns 30")
	TEST_ASSERT(pp_close(rod.percent_depleted, (3000000 - 30) / 3000000, 0.000001), "and the rod reports it")
	for(var/obj/effect/accelerated_particle/P in range(12, I))
		qdel(P)
	I.StopInjecting()
	room.requires_power = area_required

/// The hydromagnetic trap takes 20 W per K from a field within 7 tiles once its plasma is above 10000 K.
/datum/unit_test/dq_pp/fusion_trap_threshold

/datum/unit_test/dq_pp/fusion_trap_threshold/run_pp()
	var/list/run = pp_run(3)
	var/obj/effect/fusion_em_field/F = pp_fusion_field(run[1])
	var/obj/machinery/power/hydromagnetic_trap/T = allocate(/obj/machinery/power/hydromagnetic_trap, run[3])
	var/net = power_test_grid(0)
	power_test_join(net, T)
	F.plasma_temperature = 9999
	pp_step(T, PP_TRAP_STEP)
	TEST_ASSERT_EQUAL(T.icon_state, "mag_trap0", "below 10000 K it takes nothing")
	TEST_ASSERT(T.active, "but it found the field")
	F.plasma_temperature = 10001
	pp_step(T, PP_TRAP_STEP)
	TEST_ASSERT_EQUAL(T.icon_state, "mag_trap1", "above 10000 K it takes power")
	if("things_in_range" in T.vars)
		T.vars["things_in_range"] = null // the legacy trap kept its scan (itself included) in a var
	power_test_drop_grid(net)
	F.owned_core.Shutdown()

#undef PP_FIELD_STEP
#undef PP_INJECTOR_STEP
#undef PP_TRAP_STEP

// ============================================================================================ portable generators and RTGs

#define PP_GEN_STEP_PROC "gen_step"
#define PP_RTG_STEP "rtg_step"

/// A PACMAN of `type` bolted to test grid `net` with `sheets` of fuel.
/datum/unit_test/dq_pp/proc/pp_pacman(turf/T, net, sheets = 10, type = /obj/machinery/power/port_gen/pacman)
	var/obj/machinery/power/port_gen/pacman/P = allocate(type, T)
	P.set_anchored(TRUE)
	power_test_join(net, P)
	P.sheets = sheets
	return P

/// PACMAN fuel use: a step burns power_output / time_per_sheet sheets (output 4 of a basic PACMAN: 4/96 a step, so a sheet lasts 24 steps),
/// and supplies power_gen * power_output W (a persistent supply) while it runs.
/datum/unit_test/dq_pp/pacman_fuel_use

/datum/unit_test/dq_pp/pacman_fuel_use/run_pp()
	var/list/run = pp_run(1)
	var/net = power_test_grid(0)
	var/obj/machinery/power/port_gen/pacman/P = pp_pacman(run[1], net, 10)
	P.power_output = 4
	P.TogglePower()
	TEST_ASSERT(P.active, "a fuelled, bolted, wired PACMAN starts")
	pp_step(P, PP_GEN_STEP_PROC)
	TEST_ASSERT_EQUAL(P.sheets, 9, "the first step opens a sheet")
	TEST_ASSERT(pp_close(P.sheet_left, 1 - 4 / 96, 0.000001), "and burns 4/96 of it: [P.sheet_left]")
	TEST_ASSERT_EQUAL(P.power_supply_rate, P.power_gen * 4, "it supplies power_gen * 4 W: [P.power_supply_rate]")
	for(var/i in 1 to 23)
		pp_step(P, PP_GEN_STEP_PROC)
	TEST_ASSERT(pp_close(P.sheets + P.sheet_left, 9, 0.0001), "24 steps burn one sheet's worth: [P.sheets] + [P.sheet_left]")
	P.TogglePower()
	pp_step(P, PP_GEN_STEP_PROC)
	TEST_ASSERT_EQUAL(P.power_supply_rate, 0, "off, it supplies nothing")
	TEST_ASSERT(pp_close(P.sheets + P.sheet_left, 9, 0.0001), "and burns nothing")
	power_test_drop_grid(net)

/// Out of fuel it stops; the super PACMAN's uranium lasts 6 times longer (576 steps per sheet at output 1), the MRS makes 25 kW a level.
/datum/unit_test/dq_pp/pacman_fuel_out

/datum/unit_test/dq_pp/pacman_fuel_out/run_pp()
	var/list/run = pp_run(3)
	var/net = power_test_grid(0)
	var/obj/machinery/power/port_gen/pacman/P = pp_pacman(run[1], net, 0)
	P.sheet_left = 0.01
	P.power_output = 4
	P.set_active(TRUE)
	pp_step(P, PP_GEN_STEP_PROC)
	TEST_ASSERT(!P.active, "a PACMAN without the fuel for a step stops")
	TEST_ASSERT_EQUAL(P.power_supply_rate, 0, "and supplies nothing")
	var/obj/machinery/power/port_gen/pacman/super/S = pp_pacman(run[2], net, 1, /obj/machinery/power/port_gen/pacman/super)
	TEST_ASSERT_EQUAL(S.time_per_sheet, 576, "a super PACMAN's sheet lasts 576 steps at output 1")
	var/obj/machinery/power/port_gen/pacman/mrs/M = pp_pacman(run[3], net, 1, /obj/machinery/power/port_gen/pacman/mrs)
	TEST_ASSERT_EQUAL(initial(M.power_gen), 25000, "an MRS makes 25 kW a level")
	TEST_ASSERT_EQUAL(M.max_safe_output, 8, "safely up to level 8")
	power_test_drop_grid(net)

/// Heat: running at output 4 the core heats toward 56..76 + 4 * 50 K (+ the room's offset from 20 C); above max_temperature (300) it
/// overheats a count a step; switched off it cools by (T - room) / 40 (2..20) a step.
/datum/unit_test/dq_pp/pacman_heat

/datum/unit_test/dq_pp/pacman_heat/run_pp()
	var/list/room = pp_room(T20C, o2 = MOLES_O2STANDARD, n2 = MOLES_N2STANDARD)
	var/net = power_test_grid(0)
	var/obj/machinery/power/port_gen/pacman/P = pp_pacman(room[1], net, 50)
	P.power_output = 4
	P.TogglePower()
	for(var/i in 1 to 60)
		pp_step(P, PP_GEN_STEP_PROC)
	log_test("PACMAN at output 4 after 60 steps: [P.temperature] K")
	TEST_ASSERT(P.temperature >= 200 && P.temperature <= 280, "it settles in its band (256..276 K at 1 atm 20 C): [P.temperature]")
	TEST_ASSERT_EQUAL(P.overheating, 0, "below 300 it does not overheat")
	P.temperature = P.max_temperature + 10
	P.power_output = 5
	pp_step(P, PP_GEN_STEP_PROC)
	TEST_ASSERT(P.overheating >= 1, "above 300 it overheats: [P.overheating]")
	P.TogglePower()
	P.temperature = 200
	P.overheating = 0
	pp_step(P, PP_GEN_STEP_PROC)
	TEST_ASSERT(pp_close(P.temperature, 200 - round((200 - 20) / 40, 1), 0.01), "off, it cools by (T - 20) / 40: [P.temperature]")
	power_test_drop_grid(net)

/// An emag lets the output go to 2.5 times the safe maximum.
/datum/unit_test/dq_pp/pacman_emag_limit

/datum/unit_test/dq_pp/pacman_emag_limit/run_pp()
	var/list/run = pp_run(1)
	var/net = power_test_grid(0)
	var/obj/machinery/power/port_gen/pacman/P = pp_pacman(run[1], net, 10)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run[1])
	P.power_output = P.max_power_output
	TEST_ASSERT(!pp_pacman_raise(P, H), "the output stops at max_power_output")
	pp_pacman_emag(P)
	var/raised = 0
	while(pp_pacman_raise(P, H) && raised < 50)
		raised++
	TEST_ASSERT_EQUAL(P.power_output, round(P.max_power_output * 2.5), "emagged it goes to 2.5 times: [P.power_output]")
	power_test_drop_grid(net)

/// One press of the window's higher-power button: TRUE when the output went up.
/proc/pp_pacman_raise(obj/machinery/power/port_gen/pacman/P, mob/user)
	var/before = P.power_output
	var/datum/act/op/A = new
	A.actor = user
	call(P, "ui_act_higher_power")(A)
	return P.power_output > before

/// Subverts a PACMAN: its emag capability, or the legacy emagged var.
/proc/pp_pacman_emag(obj/machinery/power/port_gen/pacman/P)
	if(istype(cap_of(P, CAP_EMAG, null), /datum/capability/lib/emag))
		key_set(P, EMAG_EMAGGED, TRUE)
	else
		P.set_emagged(1)

/// RTGs supply power_gen every step: 1000 W per part rating (a basic RTG: 2000 W with its two basic parts), the advanced one 1250 per rating.
/datum/unit_test/dq_pp/rtg_output

/datum/unit_test/dq_pp/rtg_output/run_pp()
	var/list/run = pp_run(1)
	var/obj/machinery/power/rtg/R = allocate(/obj/machinery/power/rtg, run[1])
	var/rating = R.total_component_rating_of_type(/obj/item/stock_parts)
	TEST_ASSERT_EQUAL(R.power_gen, 1000 * rating, "a basic RTG makes 1000 W a rating: [R.power_gen] at rating [rating]")
	var/obj/machinery/power/rtg/advanced/A = allocate(/obj/machinery/power/rtg/advanced, run[1])
	rating = A.total_component_rating_of_type(/obj/item/stock_parts)
	TEST_ASSERT_EQUAL(A.power_gen, 1250 * rating, "an advanced one 1250 W a rating: [A.power_gen] at rating [rating]")

#undef PP_GEN_STEP_PROC
#undef PP_RTG_STEP

// ============================================================================================ the gravity generator

#define PP_GRAV_STEP "spin_step"

/// A gravity generator (no parts) on a clear floor in a powered area.
/datum/unit_test/dq_pp/proc/pp_gravgen(turf/T)
	var/area/room = get_area(T)
	room.requires_power = FALSE
	var/obj/machinery/gravity_generator/main/G = allocate(/obj/machinery/gravity_generator/main, T)
	G.power_change()
	return G

/datum/unit_test/dq_pp/proc/pp_gravgen_done(obj/machinery/gravity_generator/main/G, turf/T)
	var/area/room = get_area(T)
	room.requires_power = initial(room.requires_power)

/// Spin-up: from 0 the charge rises 2 a step; at 100 gravity comes on (the generator draws its active power) and it settles.
/datum/unit_test/dq_pp/gravgen_spin_up

/datum/unit_test/dq_pp/gravgen_spin_up/run_pp()
	var/list/run = pp_run(1)
	var/obj/machinery/gravity_generator/main/G = pp_gravgen(run[1])
	G.charge_count = 0
	G.set_use_power(USE_POWER_IDLE)
	G.set_charging_state(GRAVGEN_UP)
	pp_step(G, PP_GRAV_STEP)
	TEST_ASSERT_EQUAL(G.charge_count, 2, "a step adds 2")
	for(var/i in 1 to 49)
		pp_step(G, PP_GRAV_STEP)
	TEST_ASSERT_EQUAL(G.charge_count, 100, "50 steps reach 100")
	TEST_ASSERT_EQUAL(G.charging_state, GRAVGEN_UP, "still spinning")
	pp_step(G, PP_GRAV_STEP)
	TEST_ASSERT_EQUAL(G.charging_state, GRAVGEN_IDLE, "at 100 it settles")
	TEST_ASSERT_EQUAL(G.use_power, USE_POWER_ACTIVE, "and gravity is on")
	pp_gravgen_done(G, run[1])

/// Spin-down: the charge falls 2 a step; at 0 gravity goes off.
/datum/unit_test/dq_pp/gravgen_spin_down

/datum/unit_test/dq_pp/gravgen_spin_down/run_pp()
	var/list/run = pp_run(1)
	var/obj/machinery/gravity_generator/main/G = pp_gravgen(run[1])
	G.charge_count = 4
	G.set_use_power(USE_POWER_ACTIVE)
	G.set_charging_state(GRAVGEN_DOWN)
	pp_step(G, PP_GRAV_STEP)
	TEST_ASSERT_EQUAL(G.charge_count, 2, "a step takes 2")
	pp_step(G, PP_GRAV_STEP)
	pp_step(G, PP_GRAV_STEP)
	TEST_ASSERT_EQUAL(G.charging_state, GRAVGEN_IDLE, "at 0 it settles")
	TEST_ASSERT_EQUAL(G.use_power, USE_POWER_IDLE, "and gravity is off")
	pp_gravgen_done(G, run[1])

/// The breaker: off while running starts the spin-down; on again while spinning down starts the spin-up.
/datum/unit_test/dq_pp/gravgen_breaker

/datum/unit_test/dq_pp/gravgen_breaker/run_pp()
	var/list/run = pp_run(1)
	var/obj/machinery/gravity_generator/main/G = pp_gravgen(run[1])
	G.set_charging_state(GRAVGEN_IDLE)
	G.set_use_power(USE_POWER_ACTIVE)
	G.breaker = FALSE
	G.set_power()
	TEST_ASSERT_EQUAL(G.charging_state, GRAVGEN_DOWN, "the breaker off spins it down")
	G.breaker = TRUE
	G.set_power()
	TEST_ASSERT_EQUAL(G.charging_state, GRAVGEN_UP, "back on, it spins up again")
	pp_gravgen_done(G, run[1])

#undef PP_GRAV_STEP

// ============================================================================================ solars

/// A panel supplies solar_gen_rate * sunfrac while it is whole, linked to a controller on its own network and unobscured; sunfrac is
/// cos^2 of its angle off the sun, 0 past 90 degrees. The controller supplies the sum of its panels.
/datum/unit_test/dq_pp/solar_output

/datum/unit_test/dq_pp/solar_output/run_pp()
	var/list/run = pp_run(3)
	var/net = power_test_grid(0)
	var/obj/machinery/power/solar_control/C = allocate(/obj/machinery/power/solar_control, run[1])
	var/obj/machinery/power/solar/P = allocate(/obj/machinery/power/solar, run[2])
	power_test_join(net, C)
	power_test_join(net, P)
	TEST_ASSERT(P.set_control(C), "the panel links to its controller")
	C.add_panel(P)
	var/sun = SSsolars.get_solar_angle(get_turf(P))
	P.adir = (sun + 60) % 360
	P.obscured = 0
	P.update_solar_exposure()
	TEST_ASSERT(pp_close(P.sunfrac, 0.25, 0.001), "60 degrees off the sun is cos^2 60 = 0.25: [P.sunfrac]")
	TEST_ASSERT(pp_close(P.get_power_supplied(), GLOB.solar_gen_rate * 0.25, 0.001), "and supplies a quarter of [GLOB.solar_gen_rate] W")
	P.adir = (sun + 120) % 360
	P.update_solar_exposure()
	TEST_ASSERT_EQUAL(P.sunfrac, 0, "past 90 degrees it gets nothing")
	P.sunfrac = 1
	P.obscured = 1
	TEST_ASSERT_EQUAL(P.get_power_supplied(), 0, "obscured it supplies nothing")
	P.obscured = 0
	var/net2 = power_test_grid(0)
	power_test_join(net2, P)
	TEST_ASSERT_EQUAL(P.get_power_supplied(), 0, "off its controller's network it supplies nothing")
	power_test_join(net, P)
	TEST_ASSERT_EQUAL(P.get_power_supplied(), GLOB.solar_gen_rate, "facing the sun it supplies the full rate")
	C.remove_panel(P)
	P.unset_control()
	power_test_drop_grid(net)
	power_test_drop_grid(net2)

// ============================================================================================ the gas turbine

#define PP_COMP_STEP "compressor_step"
#define PP_TURB_STEP "turbine_step"

/// A compressor and its turbine along a run of 4 floors: the inlet, the compressor, the turbine, the outlet. list(compressor, turbine).
/datum/unit_test/dq_pp/proc/pp_turbine_pair()
	var/list/run = pp_run(4)
	var/d = pp_run_dir(run)
	var/obj/machinery/compressor/C = allocate(/obj/machinery/compressor, run[2])
	var/obj/machinery/power/turbine/T = allocate(/obj/machinery/power/turbine, run[3])
	C.set_dir(turn(d, 180))
	T.set_dir(d)
	rel_clear(C, nameof(C.turbine))
	rel_clear(T, nameof(T.compressor))
	rel_set(C, nameof(C.inturf), run[1])
	rel_set(T, nameof(T.outturf), run[4])
	C.locate_machinery()
	T.locate_machinery()
	TEST_ASSERT_EQUAL(C.turbine, T, "the compressor found its turbine")
	TEST_ASSERT_EQUAL(T.compressor, C, "and the turbine its compressor")
	C.atom_fix()
	T.atom_fix()
	return list(C, T)

/// The turbine's curve: ((rpm / 100000) ^ 0.8) * 100000 * productivity W a step.
/datum/unit_test/dq_pp/turbine_output_curve

/datum/unit_test/dq_pp/turbine_output_curve/run_pp()
	var/list/pair = pp_turbine_pair()
	var/obj/machinery/compressor/C = pair[1]
	var/obj/machinery/power/turbine/T = pair[2]
	C.set_starter(TRUE)
	C.rpm = 50000
	pp_step(T, PP_TURB_STEP)
	var/expected = ((50000 / 100000) ** 0.8) * 100000 * T.productivity
	TEST_ASSERT(pp_close(T.lastgen, expected, 0.0001), "50000 rpm makes [expected] W: [T.lastgen]")
	C.set_starter(FALSE)

/// The compressor's spin-up: started, it aims for 1000 rpm; rpm moves a tenth of the way a step and loses rpm^2 / (500000 * efficiency).
/datum/unit_test/dq_pp/compressor_spin_up

/datum/unit_test/dq_pp/compressor_spin_up/run_pp()
	var/list/pair = pp_turbine_pair()
	var/obj/machinery/compressor/C = pair[1]
	var/area/room = get_area(C)
	var/required = room.requires_power
	room.requires_power = FALSE
	C.power_change()
	C.set_starter(TRUE)
	C.rpm = 0
	C.rpmtarget = 0
	pp_step(C, PP_COMP_STEP)
	TEST_ASSERT_EQUAL(C.rpmtarget, 1000, "started, it aims for 1000 rpm")
	pp_step(C, PP_COMP_STEP)
	var/expected = 100 - (100 * 100) / (500000 * C.efficiency)
	TEST_ASSERT(pp_close(C.rpm, expected, 0.0001), "a step moves it a tenth of the way, less friction: [C.rpm], expected [expected]")
	C.set_starter(FALSE)
	room.requires_power = required

#undef PP_COMP_STEP
#undef PP_TURB_STEP
