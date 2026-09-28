// Symptoms are the effects that engineered advanced diseases do.

GLOBAL_LIST_INIT(viral_trait_types, subtypesof(/datum/viral_trait))

/datum/viral_trait
	// Buffs/Debuffs the symptom has to the overall engineered disease.
	var/name = ""
	var/desc = "ERR://355. PanDEMIC was not able to initialize description!" // Someone forgot the description
	var/threshold_descs = list()
	var/stealth = 0
	var/resistance = 0
	var/stage_speed = 0
	var/transmission = 0
	// The type level of the symptom. Higher is harder to generate.
	var/level = 0
	// The threat level of the symptom. Higher is more dangerous.
	var/threat = 0
	// The hash tag for our diseases, we will add it up with our other symptoms to get a unique id! ID MUST BE UNIQUE!!!
	var/id = ""
	var/supress_warning = FALSE
	var/next_activaction = 0
	var/symptom_delay_min = 1 SECONDS
	var/symptom_delay_max = 1 SECONDS
	var/naturally_occuring = TRUE // If this symptom can roll from random diseases

	var/base_message_chance = 10
	var/power = 1
	// If the symptom is neutered or not. If it is, it will only affect stats
	var/neutered = FALSE
	var/stopped = FALSE // Used for Viral Suspended Animaton, stops a symptom but doesn't neuter it.

	var/list/prefixes = list()
	var/list/bodies = list()
	var/list/suffixes = list()

/datum/viral_trait/New()
	var/list/S = GLOB.viral_trait_types
	for(var/i = 1; i <= length(S); i++)
		if(type == S[i])
			id = "[i]"
			return
	CRASH("We couldn't assign an ID!")

/datum/viral_trait/proc/Copy()
	var/datum/viral_trait/new_symp = new type
	new_symp.name = name
	new_symp.id = id
	new_symp.neutered = neutered
	return new_symp

// Called when processing of the advance disease, which holds this symptom, starts.
/datum/viral_trait/proc/Start(datum/affliction/contagion/engineered/A)
	if(neutered)
		return FALSE
	COOLDOWN_START(src, next_activaction, rand(symptom_delay_min, symptom_delay_max))
	return TRUE

/datum/viral_trait/proc/severityset(datum/affliction/contagion/engineered/A)
	threat = initial(threat)
	prefixes = initial(prefixes)
	bodies = initial(bodies)
	suffixes = initial(suffixes)

// Called when the advance disease is going to be deleted or when the advance disease stops processing.
/datum/viral_trait/proc/End(datum/affliction/contagion/engineered/A)
	if(neutered)
		return FALSE
	return TRUE

// Called when the disease activates. It's what makes your diseases work!
/datum/viral_trait/proc/Activate(datum/affliction/contagion/engineered/A)
	if(!A)
		return FALSE
	if(isbelly(A.host.loc)) // So you can eat people to "isolate" them. Or get eaten by a macrophage.
		return FALSE
	if(neutered || stopped)
		return FALSE
	if(!COOLDOWN_FINISHED(src, next_activaction))
		return FALSE
	else
		COOLDOWN_START(src, next_activaction, rand(symptom_delay_min, symptom_delay_max))
		return TRUE

// Called when the host dies
/datum/viral_trait/proc/OnDeath(datum/affliction/contagion/engineered/A)
	return !neutered

// Called when the stage changes
/datum/viral_trait/proc/OnStageChange(datum/affliction/contagion/engineered/A)
	if(neutered || stopped)
		return FALSE
	return TRUE

/datum/viral_trait/proc/OnAdd(datum/affliction/contagion/engineered/A)
	return

/datum/viral_trait/proc/OnRemove(datum/affliction/contagion/engineered/A)
	return

/datum/viral_trait/proc/get_symptom_data()
	var/list/data = list()
	data["name"] = name
	data["desc"] = desc
	data["stealth"] = stealth
	data["resistance"] = resistance
	data["stage_speed"] = stage_speed
	data["transmission"] = transmission
	data["neutered"] = neutered
	data["level"] = level
	data["threshold_desc"] = threshold_descs
	return data
