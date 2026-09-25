/// Verified to work with the Artifact Harvester
/datum/artifact_effect/sleepy
	name = "Drowsiness"
	effect_color = "#a36fa1"

/datum/artifact_effect/sleepy/New()
	..()
	effect_type = EFFECT_SLEEPY

/datum/artifact_effect/sleepy/DoEffectTouch(mob/toucher)
	if(toucher)
		var/weakness = GetAnomalySusceptibility(toucher)
		if(ishuman(toucher) && prob(weakness * 100))
			var/mob/living/carbon/human/H = toucher
			to_chat(H, span_blue("[pick("You feel like taking a nap.","You feel a yawn coming on.","You feel a little tired.")]"))
			H.status_set(EFFECT_DROWSY, min(H.status_units(EFFECT_DROWSY) + rand(5,25) * weakness, 50 * weakness))
			H.status_set(EFFECT_BLURRY, min(H.status_units(EFFECT_BLURRY) + rand(1,3) * weakness, 50 * weakness))
			return 1
		else if(isrobot(toucher))
			to_chat(toucher, span_red("SYSTEM ALERT: CPU cycles slowing down."))
			return 1

/datum/artifact_effect/sleepy/DoEffectAura()
	var/atom/holder = get_master_holder()
	if(holder)
		var/turf/T = get_turf(holder)
		for (var/mob/living/carbon/human/H in range(src.effectrange,T))
			var/weakness = GetAnomalySusceptibility(H)
			if(prob(weakness * 100))
				if(prob(10))
					to_chat(H, span_blue("[pick("You feel like taking a nap.","You feel a yawn coming on.","You feel a little tired.")]"))
				H.status_set(EFFECT_DROWSY, min(H.status_units(EFFECT_DROWSY) + 1 * weakness, 25 * weakness))
				H.status_set(EFFECT_BLURRY, min(H.status_units(EFFECT_BLURRY) + 1 * weakness, 25 * weakness))
		for (var/mob/living/silicon/robot/R in range(src.effectrange,holder))
			to_chat(R, span_red("SYSTEM ALERT: CPU cycles slowing down."))
		return 1

/datum/artifact_effect/sleepy/DoEffectPulse()
	var/atom/holder = get_master_holder()
	if(holder)
		var/turf/T = get_turf(holder)
		for(var/mob/living/carbon/human/H in range(src.effectrange, T))
			var/weakness = GetAnomalySusceptibility(H)
			if(prob(weakness * 100))
				to_chat(H, span_blue("[pick("You feel like taking a nap.","You feel a yawn coming on.","You feel a little tired.")]"))
				H.status_set(EFFECT_DROWSY, min(H.status_units(EFFECT_DROWSY) + rand(5,15) * weakness, 50 * weakness))
				H.status_set(EFFECT_BLURRY, min(H.status_units(EFFECT_BLURRY) + rand(5,15) * weakness, 50 * weakness))
		for (var/mob/living/silicon/robot/R in range(src.effectrange,holder))
			to_chat(R, span_red("SYSTEM ALERT: CPU cycles slowing down."))
		return 1
