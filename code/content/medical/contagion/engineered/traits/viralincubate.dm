/datum/viral_trait/viralincubate
	name = "Viral Suspended Animation"
	desc = "The virus has very little effect until it reaches its final stage"
	stealth = 4
	resistance = -2
	stage_speed = -2
	transmission = 1
	level = 4
	symptom_delay_min = 1
	symptom_delay_max = 1
	var/list/captives
	var/used = FALSE

/datum/viral_trait/viralincubate/Activate(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	if(A.stage >= 5)
		for(var/datum/viral_trait/S as anything in captives)
			S.stopped = FALSE
			rel_remove(src, nameof(captives), S)
		if(!LAZYLEN(captives))
			stopped = TRUE
	else if(!used)
		for(var/datum/viral_trait/S as anything in A.symptoms)
			if(S.neutered)
				continue
			if(S == src)
				continue
			S.stopped = TRUE
			rel_add(src, nameof(captives), S)
		used = TRUE

CAPABILITIES(/datum/viral_trait/viralincubate)
	ref_many(nameof(captives))
