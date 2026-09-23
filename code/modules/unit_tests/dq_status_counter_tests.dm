// Unit tests for the status counters (code/modules/mob/living/life/status_counters.dm) and
// for human hibernation (doc/mob_life_architecture.md §4.7, §4.9): every counter applies,
// expires on its own timer and wakes the mob at both ends; the raw counter vars are gone; a
// healthy idle human hibernates, and injury, reagents, stuns, equipment and speech wake it.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Every counter type with the setter that starts it.
/proc/status_counter_test_cases()
	return list(
		/datum/status_effect/counter/stunned = "Stun",
		/datum/status_effect/counter/weakened = "Weaken",
		/datum/status_effect/counter/paralysis = "Paralyse",
		/datum/status_effect/counter/sleeping = "Sleeping",
		/datum/status_effect/counter/confused = "Confuse",
		/datum/status_effect/counter/blind = "Blind",
		/datum/status_effect/counter/blurry = "Blur",
		/datum/status_effect/counter/druggy = "Drug",
		/datum/status_effect/counter/deaf = "Deafen",
		/datum/status_effect/counter/drowsy = "Drowse",
		/datum/status_effect/counter/silent = "Silence",
		/datum/status_effect/counter/stuttering = "Stutter",
		/datum/status_effect/counter/slurring = "Slur",
	)

/// Every counter starts through its setter, wakes a hibernating mob, runs on its own timer
/// while the mob hibernates, and wakes it again when it runs out.
/datum/unit_test/dq_status_counters_apply_expire_and_wake

/datum/unit_test/dq_status_counters_apply_expire_and_wake/Run()
	var/list/cases = status_counter_test_cases()
	for(var/counter_type in cases)
		var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
		TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
		M.status_flags |= CANSTUN | CANWEAKEN | CANPARALYSE
		TEST_ASSERT(life_test_settle(M), "[counter_type]: the mouse should hibernate first; still busy: [life_test_busy(M)]")
		call(M, cases[counter_type])(4)
		var/datum/status_effect/counter/C = M.has_status_effect(counter_type)
		TEST_ASSERT_NOTNULL(C, "[cases[counter_type]]() should start [counter_type]")
		TEST_ASSERT(M.status_counter(counter_type) > 3.9, "[counter_type] should hold four ticks, got [M.status_counter(counter_type)]")
		TEST_ASSERT(C.duration > world.time, "[counter_type] should own a deadline")
		TEST_ASSERT(!M.life_hibernating, "[counter_type] starting should wake a hibernating mob")
		TEST_ASSERT(life_test_settle(M, 12), "[counter_type] needs no Life() ticks, so the mouse should hibernate while it runs; still busy: [life_test_busy(M)]")
		TEST_ASSERT(life_test_expire_counter(M, counter_type), "[counter_type] should end at its deadline")
		TEST_ASSERT_EQUAL(M.status_counter(counter_type), 0, "[counter_type] should have worn off")
		TEST_ASSERT(!M.life_hibernating, "[counter_type] ending should wake the mob")
		TEST_ASSERT_NULL(M.life_missed_wake(), "[counter_type] should leave no missed wake behind")

/// The setters keep their legacy semantics: X() never lowers, SetX() sets, AdjustX() adds
/// and never goes below zero.
/datum/unit_test/dq_status_counter_setter_semantics

/datum/unit_test/dq_status_counter_setter_semantics/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.Blur(10)
	H.Blur(3)
	TEST_ASSERT(H.get_eye_blurry() > 9.9, "Blur() must not lower a longer blur, got [H.get_eye_blurry()]")
	H.SetBlurry(3)
	TEST_ASSERT(abs(H.get_eye_blurry() - 3) < 0.01, "SetBlurry() sets the blur, got [H.get_eye_blurry()]")
	H.AdjustBlurry(2)
	TEST_ASSERT(abs(H.get_eye_blurry() - 5) < 0.01, "AdjustBlurry() adds, got [H.get_eye_blurry()]")
	H.AdjustBlurry(-10)
	TEST_ASSERT_EQUAL(H.get_eye_blurry(), 0, "AdjustBlurry() never goes below zero")
	TEST_ASSERT_NULL(H.has_status_effect(/datum/status_effect/counter/blurry), "a counter at zero no longer exists")
	H.Silence(5)
	TEST_ASSERT(H.action_blocked(ACTION_BLOCK_SPEECH), "silence blocks speech through its action block")
	H.SetSilent(0)
	TEST_ASSERT(!H.action_blocked(ACTION_BLOCK_SPEECH), "the speech block ends with the silence")
	H.Deafen(5)
	TEST_ASSERT(isdeaf(H), "deafness makes the mob deaf")

/// The raw counter vars are gone: counters are written through their setters only
/// (tools/ci/check_grep.sh rejects direct writes to the old names).
/datum/unit_test/dq_status_counter_direct_write_ban

/datum/unit_test/dq_status_counter_direct_write_ban/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/list/names = list("stunned", "weakened", "paralysis", "sleeping", "confused", "eye_blind", "eye_blurry", "druggy", "ear_deaf", "drowsyness", "silent", "stuttering", "slurring")
	for(var/name in names)
		TEST_ASSERT(!(name in H.vars), "[name] is a status counter datum, not a mob var")
	var/list/getters = list("get_stunned", "get_weakened", "get_paralysis", "get_sleeping", "get_confused", "get_eye_blind", "get_eye_blurry", "get_druggy", "get_ear_deaf", "get_drowsyness", "get_silent", "get_stuttering", "get_slurring")
	for(var/getter in getters)
		TEST_ASSERT(hascall(H, getter), "[getter]() should read the counter")
		TEST_ASSERT_EQUAL(call(H, getter)(), 0, "[getter]() reads 0 while the counter isn't running")

// --- Human hibernation -------------------------------------------------------------------

/// Puts a test human on a floor in breathable, comfortable air (the healthy idle case).
/proc/life_test_place_in_air(mob/living/carbon/human/H)
	var/checked = 0
	for(var/turf/simulated/floor/T in world)
		if(++checked > 5000)
			break
		var/datum/gas_mixture/air = T.return_air()
		if(!air)
			continue
		var/pressure = air.return_pressure()
		if(pressure < 90 || pressure > 110)
			continue
		if(abs(air.return_temperature() - T20C) > 5)
			continue
		if(LINDA_GAS_AMT(air, GAS_O2) / max(air.total_moles(), 0.01) < 0.19)
			continue
		// Only oxygen and nitrogen: other tests leave stray gas on shared floors.
		if((LINDA_GAS_AMT(air, GAS_O2) + LINDA_GAS_AMT(air, GAS_N2)) / max(air.total_moles(), 0.01) < 0.999)
			continue
		if(locate(/mob/living) in T)
			continue
		H.forceMove(T)
		return TRUE
	return FALSE

/// Settles a test human: all systems run until each has declared itself idle.
/proc/life_test_settle_human(mob/living/carbon/human/H, cycles = 16)
	return life_test_settle(H, cycles)

/// What keeps a human's organs system awake, for failure messages.
/proc/life_test_organ_reasons(mob/living/carbon/human/H)
	var/list/reasons = list()
	if(length(H.bad_external_organs))
		reasons += "limbs [jointext(H.bad_external_organs, ",")]"
	if(H.stance_damage)
		reasons += "stance [H.stance_damage]"
	if(LAZYLEN(H.body?.afflictions))
		reasons += "afflictions [length(H.body.afflictions)]"
	if(H.bloodstr?.total_volume || H.ingested?.total_volume)
		reasons += "reagents"
	for(var/obj/item/organ/I as anything in H.internal_organs)
		if(!I.life_quiescent())
			reasons += "[I.type] (damage [I.damage], germs [I.germ_level])"
	return jointext(reasons, "; ")

/// A healthy, idle human in normal air with no afflictions puts every system to sleep and
/// leaves the SSmobs run.
/datum/unit_test/dq_life_idle_human_hibernates

/datum/unit_test/dq_life_idle_human_hibernates/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place_in_air(H), "no floor with breathable air for the test human")
	TEST_ASSERT(life_test_settle_human(H), "an idle healthy human should hibernate; still busy: [life_test_busy(H)]; awake bits [H.life_awake]; organs: [life_test_organ_reasons(H)]")
	TEST_ASSERT(H in SSmobs.hibernating_mobs, "a hibernating human is parked in SSmobs")
	TEST_ASSERT_NULL(H.life_missed_wake(), "a freshly hibernated human has no missed wake")
	TEST_ASSERT_NULL(SSmobs.audit_mob(H), "the audit must not flag a human that is correctly asleep")

/// A clientless (SSD) human holds one permanent sleep that nothing processes, hibernates in
/// clean air, and stays hibernating while real time passes. Occupying the body releases it.
/datum/unit_test/dq_life_ssd_human_hibernates

/datum/unit_test/dq_life_ssd_human_hibernates/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place_in_air(H), "no floor with breathable air for the test human")
	TEST_ASSERT(H.sleep_should_hold(), "a clientless, unoccupied human is SSD")
	TEST_ASSERT(life_test_settle_human(H), "an SSD human should hibernate; still busy: [life_test_busy(H)]; awake bits [H.life_awake]; organs: [life_test_organ_reasons(H)]; stat [H.stat] sleeping [H.get_sleeping()]")
	var/datum/status_effect/counter/sleeping/S = H.has_status_effect(/datum/status_effect/counter/sleeping)
	TEST_ASSERT(S, "an SSD human is asleep")
	TEST_ASSERT(S.is_held(), "the SSD sleep is held (permanent), not re-applied on a timer; duration [S.duration] now [world.time]")
	TEST_ASSERT(!(S in SSfastprocess.processing), "a held sleep is not processed")
	TEST_ASSERT_EQUAL(H.stat, UNCONSCIOUS, "an SSD human is unconscious")

	// Several SSmobs cycles of real time; the shortest human rewake timer is 10 seconds.
	for(var/i in 1 to 4)
		sleep(STATUS_COUNTER_TICK)
		TEST_ASSERT(H.life_hibernating, "the SSD human stays hibernating (cycle [i]); awake bits [H.life_awake]; busy: [life_test_busy(H)]")
	TEST_ASSERT(S == H.has_status_effect(/datum/status_effect/counter/sleeping) && S.is_held(), "the same held sleep persists, never re-applied")
	TEST_ASSERT_NULL(H.life_missed_wake(), "a hibernating SSD human has no missed wake")

	// Someone takes the body over: the producer releases the hold and wakes the mob.
	H.teleop = allocate(/mob)
	H.on_client_changed("login")
	TEST_ASSERT(!H.life_hibernating, "occupying the body wakes it")
	TEST_ASSERT(!S.is_held(), "occupying the body releases the held sleep")
	TEST_ASSERT(S in SSfastprocess.processing, "a released sleep runs out on its own")

/// Each normal interaction wakes a hibernating human: injury, a reagent, a stun, equipment
/// and speech.
/datum/unit_test/dq_life_interactions_wake_human

/datum/unit_test/dq_life_interactions_wake_human/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	// Occupied, so it isn't SSD: a clientless, unpiloted human is put to sleep every tick,
	// and this test checks an awake human's canmove and sight.
	H.teleop = allocate(/mob)
	TEST_ASSERT(life_test_place_in_air(H), "no floor with breathable air for the test human")

	TEST_ASSERT(life_test_settle_human(H), "the human should hibernate first; still busy: [life_test_busy(H)]; awake bits [H.life_awake]; organs: [life_test_organ_reasons(H)]; body settled [H.body?.life_settled()] dirty [H.body?.dirty] factors [H.body?.factors ? "yes" : "none"]; breath quality [H.body?.physiology?.breath_quality]; stat [H.stat]")
	TEST_ASSERT(H.injure(INJURY_BLUNT, 5, BP_TORSO) > 0, "the injury should land")
	TEST_ASSERT(!H.life_hibernating, "injure() should wake a hibernating human")
	TEST_ASSERT(H.life_awake & LIFE_SYS_BODY, "injure() should wake the body systems")
	H.fully_heal()

	TEST_ASSERT(life_test_settle_human(H), "the healed human should hibernate again; still busy: [life_test_busy(H)]; awake bits [H.life_awake]; organs: [life_test_organ_reasons(H)]; body settled [H.body?.life_settled()] dirty [H.body?.dirty] factors [H.body?.factors ? "yes" : "none"]; breath quality [H.body?.physiology?.breath_quality]; stat [H.stat]")
	H.bloodstr.add_reagent(REAGENT_ID_WATER, 5)
	TEST_ASSERT(!H.life_hibernating, "a reagent should wake a hibernating human")
	TEST_ASSERT(H.life_awake & LIFE_SYS_METABOLISM, "a reagent should wake metabolism")
	H.bloodstr.clear_reagents()

	TEST_ASSERT(life_test_settle_human(H), "the human should hibernate again; still busy: [life_test_busy(H)]; awake bits [H.life_awake]; organs: [life_test_organ_reasons(H)]; body settled [H.body?.life_settled()] dirty [H.body?.dirty] factors [H.body?.factors ? "yes" : "none"]; breath quality [H.body?.physiology?.breath_quality]; stat [H.stat]")
	H.Stun(3)
	TEST_ASSERT(!H.life_hibernating, "Stun() should wake a hibernating human")
	TEST_ASSERT(!H.canmove, "a stunned human can't move")
	TEST_ASSERT(life_test_expire_counter(H, /datum/status_effect/counter/stunned), "the stun should end at its deadline")
	TEST_ASSERT(H.canmove, "the end of the stun restores canmove; stat [H.stat] stunned [H.get_stunned()] weakened [H.get_weakened()] paralysis [H.get_paralysis()] sleeping [H.get_sleeping()] resting [H.resting] lying [H.lying] buckled [H.buckled] grabbed [length(H.grabbed_by)] effects [json_encode(H.status_effects)]")

	TEST_ASSERT(life_test_settle_human(H), "the human should hibernate again after the stun; still busy: [life_test_busy(H)]; awake bits [H.life_awake]; organs: [life_test_organ_reasons(H)]; body settled [H.body?.life_settled()] dirty [H.body?.dirty] factors [H.body?.factors ? "yes" : "none"]; breath quality [H.body?.physiology?.breath_quality]; stat [H.stat]")
	var/obj/item/clothing/glasses/sunglasses/blindfold/B = allocate(/obj/item/clothing/glasses/sunglasses/blindfold)
	TEST_ASSERT(H.equip_to_slot_if_possible(B, slot_glasses), "the blindfold should go on")
	TEST_ASSERT(!H.life_hibernating, "equipping something should wake a hibernating human")
	TEST_ASSERT(H.life_awake & LIFE_SYS_SENSES, "equipment should wake the senses")
	H.Life()
	TEST_ASSERT(H.blinded, "the blindfold blinds on the woken cycle, not by a per-tick reset")
	H.drop_from_inventory(B)
	H.Life()
	TEST_ASSERT(!H.blinded, "taking the blindfold off restores sight")

	TEST_ASSERT(life_test_settle_human(H), "the human should hibernate again after the blindfold; still busy: [life_test_busy(H)]; awake bits [H.life_awake]; organs: [life_test_organ_reasons(H)]; body settled [H.body?.life_settled()] dirty [H.body?.dirty] factors [H.body?.factors ? "yes" : "none"]; breath quality [H.body?.physiology?.breath_quality]; stat [H.stat]")
	H.Stutter(4)
	TEST_ASSERT(!H.life_hibernating, "a speech impairment should wake a hibernating human")
	TEST_ASSERT(H.get_stuttering() > 3.9, "the stutter should land")
	TEST_ASSERT(life_test_settle_human(H), "a stutter runs on its own timer, so the human hibernates while stuttering; still busy: [life_test_busy(H)]; awake bits [H.life_awake]; organs: [life_test_organ_reasons(H)]; body settled [H.body?.life_settled()] dirty [H.body?.dirty] factors [H.body?.factors ? "yes" : "none"]; breath quality [H.body?.physiology?.breath_quality]; stat [H.stat]")
	TEST_ASSERT(life_test_expire_counter(H, /datum/status_effect/counter/stuttering), "the stutter should end at its deadline")
	TEST_ASSERT(!H.life_hibernating, "the end of the stutter wakes the human")
	TEST_ASSERT_NULL(H.life_missed_wake(), "no interaction should leave a missed wake behind")

/// The physiology sleeps once settled, and a timed support wakes it for its expiry.
/datum/unit_test/dq_life_physiology_sleep_rule

/datum/unit_test/dq_life_physiology_sleep_rule/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place_in_air(H), "no floor with breathable air for the test human")
	var/datum/life_system/physiology/P = get_life_system(/datum/life_system/physiology)
	H.body.ensure_physiology()
	TEST_ASSERT(P.idle(H), "a healthy body's physiology should be settled")
	var/datum/body_support/S = H.body.add_support(H, BF_RESP_DRIVE, 1, 10 SECONDS)
	TEST_ASSERT_NOTNULL(S, "the support should be added")
	TEST_ASSERT(!P.idle(H), "a timed support keeps the physiology awake")
	TEST_ASSERT(H.life_timer_id && (H.life_timer_bits & LIFE_SYS_BODY), "a timed support schedules a wake for its expiry")
	H.body.remove_supports(H)
	H.body.ensure_physiology()
	TEST_ASSERT(P.idle(H), "the physiology settles again once the support is gone")
	H.add_oxygen_debt(20, "test")
	TEST_ASSERT(!P.idle(H), "oxygen debt keeps the physiology awake")

#endif
