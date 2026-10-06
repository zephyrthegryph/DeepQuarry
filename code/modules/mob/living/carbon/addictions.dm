// Addictions

// Addictions work using a combined counter var. If a reagent is in the list returned by get_addictive_reagents(), it will be added to the addiction_counters[] assoc list by its id.
// If it is present in your body, and you are NOT addicted, it will count DOWNWARD. When it reaches the "addiction proc" you will become addicted. By default you will become addicted at
// ADDICTION_PROC negative points. FASTADDICT_PROC and SLOWADDICT_PROC are also used depending on the reagent's addiction speed. This is to prevent booze being as addictive as bliss.
// If you are addicted to a chem, and have it present in your body, the counter will quickly climb back up to ADDICTION_PEAK. Refreshing your addiction entirely.

// Once the addiction proc is reached you will become addicted. The counter will be set to ADDICTION_PEAK and begin counting DOWNWARD. Each addicted reagent has a handle_addiction() proc. The default
// implimentation of it will perform various effects once you are under 100 points of addiction. Such as vomiting, organ damage, and other bad effects for not feeding the addiction. Check that
// code for exact logic. Inaprovaline is intended to suppress withdrawl effects. Reagents may override the handle_addiction proc to have their own special handling. Like reagents that kill you if you
// do not feed their withdrawls. The handle_addiction proc also handles if you become cured of your addiction! If it returns 0, it will end your addiction.

// Faster addictions
#define SLOWADDICT_PROC -1750
#define ADDICTION_PROC -1000
#define FASTADDICT_PROC -750
#define POISONADDICT_PROC -100
#define ADDICTION_PEAK 250

/mob/living/carbon/proc/sync_addictions()
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!species)
		return
	if(!species.traits)
		return
	// Rebuild addictions from traits
	LAZYCLEARLIST(addictions)
	LAZYCLEARLIST(addiction_counters)
	for(var/TR in species.traits)
		var/datum/trait/T = GLOB.all_traits[TR]
		if(!T)
			continue
		if(!T.addiction)
			continue
		addict_to_reagent(T.addiction, TRUE)

/mob/living/proc/life_addictions_rewake()
	return 0

/// Cravings and withdrawal.
/mob/living/proc/life_addictions(datum/seq_frame/life/F)
	return

/mob/living/proc/life_addictions_due()
	return FALSE

/// MED-6: no addiction to build, feed or withdraw from.
/mob/living/carbon/life_addictions_due()
	if(src.has_addictions())
		return TRUE
	var/list/addictive = get_addictive_reagents(ADDICT_ALL)
	for(var/datum/reagent/R as anything in src.bloodstr?.reagent_list)
		if((R.id in addictive) || istype(R, /datum/reagent/ethanol))
			return TRUE
	for(var/datum/reagent/R as anything in src.ingested?.reagent_list)
		if((R.id in addictive) || istype(R, /datum/reagent/ethanol) || istype(R, /datum/reagent/drink/coffee))
			return TRUE
	return FALSE

/mob/living/carbon/life_addictions_rewake()
	return 30 SECONDS

/mob/living/carbon/life_addictions(datum/seq_frame/life/F)
	src.process_addictions()

/// Builds, feeds and withdraws addictions from the reagents in the blood and gut.
/mob/living/carbon/proc/process_addictions()
	// Don't process during vore stuff... It was originally just absorbed, but lets give some mercy to rp focused servers.
	if(isbelly(loc))
		return
	// All addictions start at 0.
	var/list/addict = list()
	for(var/datum/reagent/R in bloodstr.reagent_list)
		var/reagentid = R.id
		if(istype(SSchemistry.ready().chemical_reagents[reagentid], /datum/reagent/ethanol))
			reagentid = REAGENT_ID_ETHANOL
		if(reagentid in get_addictive_reagents(ADDICT_ALL))
			addict.Add(reagentid)
	// Only needed for alcohols, will interfere with pills if you detect other things!
	for(var/datum/reagent/R in ingested.reagent_list)
		var/reagentid = R.id
		if(istype(SSchemistry.ready().chemical_reagents[reagentid], /datum/reagent/ethanol))
			reagentid = REAGENT_ID_ETHANOL
		if(istype(SSchemistry.ready().chemical_reagents[reagentid], /datum/reagent/drink/coffee))
			reagentid = REAGENT_ID_COFFEE
		if(reagentid in get_addictive_reagents(ADDICT_ALL))
			addict.Add(reagentid)

	for(var/A in addict)
		if(!LAZYFIND(addictions,A))
			LAZYADD(addictions,A)
			LAZYSET(addiction_counters,A,0)

		if(LAZYACCESS(addiction_counters,A) <= 0)
			// Build addiction until it procs
			if(LAZYFIND(addiction_counters, A))
				addiction_counters[A] -= rand(1,3)

			if(LAZYACCESS(addiction_counters,A) < SLOWADDICT_PROC)
				LAZYSET(addiction_counters,A,SLOWADDICT_PROC)
			// Check for addiction: one chain, so a SLOW reagent never falls through to the
			// normal threshold (B10).
			if(A in get_addictive_reagents(ADDICT_SLOW))
				// Slowest addictions for some medications
				if(LAZYACCESS(addiction_counters,A) <= SLOWADDICT_PROC)
					addict_to_reagent(A, FALSE)
			else if(A in get_addictive_reagents(ADDICT_FAST))
				// quickly addict to these drugs, bliss, oxyco etc
				if(LAZYACCESS(addiction_counters,A) <= FASTADDICT_PROC)
					addict_to_reagent(A, FALSE)
			else
				// slower addiction over a longer period, cigs and painkillers mostly
				if(LAZYACCESS(addiction_counters,A) <= ADDICTION_PROC)
					addict_to_reagent(A, FALSE)
		else
			// satiating addiction we already have
			if(LAZYACCESS(addiction_counters,A) < ADDICTION_PEAK)
				if(LAZYACCESS(addiction_counters,A) < 100)
					LAZYSET(addiction_counters,A,100)
					var/datum/reagent/RR = SSchemistry.ready().chemical_reagents[A]
					var/message = RR.addiction_refresh_message()
					if(message)
						to_chat(src, message)
				if(LAZYFIND(addiction_counters, A))
					addiction_counters[A] += rand(8,13)

	// For all counters above 100, count down
	// For all under 0, count up to 0 randomly, reducing initial addiction buildup if you didn't proc it
	if(LAZYLEN(addictions))
		var/C = pick(addictions)
		// return to normal... we didn't haven't been addicted yet, but we shouldn't become addicted instantly next time if it's been a few hours!
		if(LAZYACCESS(addiction_counters,C) < 0)
			if(prob(15) && LAZYFIND(addiction_counters, C))
				addiction_counters[C] += 1
		// proc reagent's withdrawl
		var/datum/reagent/RE = SSchemistry.ready().chemical_reagents[C]
		var/addict_counter_before = LAZYACCESS(addiction_counters,C)
		if(LAZYACCESS(addiction_counters,C) > 0)
			var/withdrawal_counter = RE.handle_addiction(src,species.reagent_tag)
			LAZYSET(addiction_counters,C,withdrawal_counter) // withdrawl can modify the value however it deems fit as you are affected by it
		// remove if finished
		if(LAZYACCESS(addiction_counters,C) == 0)
			var/message = RE.addiction_cure_message()
			if(addict_counter_before > 0 && message) // Only show cure message if we were addicted to it prior!
				to_chat(src, message)
			LAZYREMOVE(addictions,C)
			LAZYREMOVE(addiction_counters,C)

/mob/living/carbon/proc/addict_to_reagent(reagentid, round_start)
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(HAS_SYNTHETIC_BIOLOGY(src)) // Should this be allowed? I guess you can roleplay Bender as an FBP? Trait in the future?
		return
	// Check if serverconfig allows addiction during the round. Otherwise only allow spawning with addictions
	var/allow_addiction = round_start || CONFIG_GET(flag/can_addict_during_round)
	if(!allow_addiction)
		return
	if(!LAZYFIND(addictions,reagentid))
		LAZYADD(addictions,reagentid)
	LAZYSET(addiction_counters,reagentid,ADDICTION_PEAK)

/// Any addiction tracked (built up, active or in withdrawal)? Read by the addictions life stage.
/mob/living/carbon/proc/has_addictions()
	SHOULD_NOT_OVERRIDE(TRUE)
	return LAZYLEN(addictions) > 0

/// Sets a reagent's not-yet-addicted build-up counter (negative), e.g. to seed a scenario.
/mob/living/carbon/proc/set_addiction_buildup(reagentid, value)
	SHOULD_NOT_OVERRIDE(TRUE)
	LAZYOR(addictions, reagentid)
	LAZYSET(addiction_counters, reagentid, min(value, 0))

/mob/living/carbon/proc/get_addiction_to_reagent(reagentid) // returns counter's value or 0
	SHOULD_NOT_OVERRIDE(TRUE)
	return LAZYACCESS(addiction_counters,reagentid)

/mob/living/carbon/proc/refresh_all_addictions()
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!addiction_counters)
		return
	for(var/reagentid in addiction_counters)
		LAZYSET(addiction_counters,reagentid,ADDICTION_PEAK)

/mob/living/carbon/proc/clear_all_addictions() // This is probably not a good idea to call as some addictions are intended to be uncurable, like artificial sustenance.
	SHOULD_NOT_OVERRIDE(TRUE)
	LAZYCLEARLIST(addictions)
	LAZYCLEARLIST(addiction_counters)

/mob/living/carbon/proc/get_all_addictions()
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)
	var/list/addict = list()
	if(addiction_counters)
		for(var/key in addiction_counters)
			addict.Add(key)
	return addict

#undef ADDICTION_PROC
#undef SLOWADDICT_PROC
#undef FASTADDICT_PROC
#undef POISONADDICT_PROC
#undef ADDICTION_PEAK

/proc/get_addictive_reagents(addict_type)
	RETURN_TYPE(/list)
	switch(addict_type)
		if(ADDICT_NORMAL)
			return GLOB.reagent_addictive_standard // Most reagents go here
		if(ADDICT_SLOW)
			return GLOB.reagent_addictive_slow	// Booze, Cigs
		if(ADDICT_FAST)
			return GLOB.reagent_addictive_fast	// Bliss, hyperzine, hardcore drugs
		if(ADDICT_POISON)
			return GLOB.reagent_addictive_poison // Poisons that use handle_addiction() for unique longterm poisoning
	// The union is built once (the tables are constant) instead of per call.
	return GLOBAL_TABLE_GET(reagent_addictive_all)

GLOBAL_TABLE(reagent_addictive_all, GLOBAL_PROC_REF(build_reagent_addictive_all))

/proc/build_reagent_addictive_all()
	return GLOB.reagent_addictive_standard + GLOB.reagent_addictive_fast + GLOB.reagent_addictive_slow + GLOB.reagent_addictive_poison
