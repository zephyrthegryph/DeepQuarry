// A fixed body-factor workload for comparing cache and observation changes.
// Setup and teardown are outside the timed phases.

/datum/modifier/benchmark_factor_churn
	name = "benchmark factor source"
	factors = alist(BF_HEALING_RECEIVED = 2)

/// Factor source without autonomous progression, treatment, or symptoms.
/datum/affliction/benchmark_factor_churn
	name = "benchmark factor source"
	progression_rate = 0
	min_symptoms = 0
	max_symptoms = 0
	spontaneous_emote_prob = 0
	factors = alist(BF_HEART_RATE = 20)

/datum/benchmark/body_factor_churn
	id = "body_factor_churn"
	description = "Body factor reads, severity and modifier changes, and observed views"

/datum/benchmark/body_factor_churn/Run()
	wait_for_assets()
	var/count = clamp(round(param("mobs", 64)), 1, 200)
	var/rounds = clamp(round(param("rounds", 16)), 1, 80)
	var/list/turf/open/floors = build_floor_fixture(12)
	var/list/mob/living/carbon/human/mobs = list()
	var/list/datum/affliction/benchmark_factor_churn/afflictions = list()
	var/list/datum/modifier/benchmark_factor_churn/modifiers = list()
	var/list/datum/object_model/derived_watch/watches = list()
	for(var/i in 1 to count)
		var/mob/living/carbon/human/H = new(pick(floors))
		var/datum/affliction/benchmark_factor_churn/A = H.body.afflict(/datum/affliction/benchmark_factor_churn)
		if(!A)
			fail("could not create benchmark affliction")
		A.set_severity(100)
		var/datum/modifier/benchmark_factor_churn/M = H.add_modifier(/datum/modifier/benchmark_factor_churn)
		if(!M)
			fail("could not create benchmark modifier")
		mobs += H
		afflictions += A
		modifiers += M
		if(i % 2 == 0)
			watches += H.body.observe_factor_view(src)
			H.body.factor_view()
		if(H.factor(BF_HEART_RATE) != 20 || H.factor(BF_HEALING_RECEIVED) != 2)
			fail("incorrect initial body factors")
		CHECK_TICK
	metric("mobs", count, "mobs", "none")
	metric("observed_bodies", length(watches), "bodies", "none")
	metric("iterations", count * rounds, "mob-rounds", "none")

	var/checksum = 0
	rustg_time_reset("body_factor_churn_reads")
	for(var/round in 1 to rounds)
		for(var/mob/living/carbon/human/H as anything in mobs)
			checksum += H.factor(BF_HEART_RATE) + H.factor(BF_HEALING_RECEIVED)
	metric("stable_reads_us_per_mob_round", rustg_time_microseconds("body_factor_churn_reads") / (count * rounds), "us/mob-round")

	// These writes change severity and vitals without changing the rounded
	// factor contribution. Observed views should avoid recomputing their vector.
	for(var/i in 1 to count)
		var/datum/affliction/benchmark_factor_churn/A = afflictions[i]
		var/mob/living/carbon/human/H = mobs[i]
		A.set_severity(98)
		H.factor(BF_HEART_RATE)
		if(i % 2 == 0)
			H.body.factor_view()
	rustg_time_reset("body_factor_churn_same_band")
	for(var/round in 1 to rounds)
		var/severity = (round % 2) ? 99 : 98
		for(var/i in 1 to count)
			var/datum/affliction/benchmark_factor_churn/A = afflictions[i]
			var/mob/living/carbon/human/H = mobs[i]
			A.set_severity(severity)
			checksum += H.factor(BF_HEART_RATE)
			if(i % 2 == 0)
				var/list/view = H.body.factor_view()
				checksum += view[BF_HEART_RATE]
	metric("same_band_us_per_mob_round", rustg_time_microseconds("body_factor_churn_same_band") / (count * rounds), "us/mob-round")

	rustg_time_reset("body_factor_churn_writes")
	for(var/round in 1 to rounds)
		var/severity = (round % 2) ? 50 : 100
		var/healing = (round % 2) ? 0.5 : 2
		for(var/i in 1 to count)
			var/datum/affliction/benchmark_factor_churn/A = afflictions[i]
			var/datum/modifier/benchmark_factor_churn/M = modifiers[i]
			var/mob/living/carbon/human/H = mobs[i]
			A.set_severity(severity)
			M.set_factors(alist(BF_HEALING_RECEIVED = healing))
			checksum += H.factor(BF_HEART_RATE) + H.factor(BF_HEALING_RECEIVED)
			if(i % 2 == 0)
				var/list/view = H.body.factor_view()
				checksum += view[BF_HEART_RATE] + view[BF_HEALING_RECEIVED]
	metric("churn_us_per_mob_round", rustg_time_microseconds("body_factor_churn_writes") / (count * rounds), "us/mob-round")
	var/odd_rounds = round((rounds + 1) / 2)
	var/even_rounds = rounds - odd_rounds
	var/reads_per_round = count + length(watches)
	var/expected = count * rounds * 22 + reads_per_round * rounds * 19.6 + reads_per_round * (odd_rounds * 10.5 + even_rounds * 22)
	// DM's repeated decimal addition can differ slightly from closed-form arithmetic.
	if(abs(checksum - expected) > 2)
		fail("factor checksum drifted: got [checksum], expected [expected]")
	metric("checksum", checksum, "factor units", "none")
	for(var/datum/object_model/derived_watch/watch as anything in watches)
		qdel(watch)
	for(var/mob/living/carbon/human/H as anything in mobs)
		qdel(H)
		CHECK_TICK
