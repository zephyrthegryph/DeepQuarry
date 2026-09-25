/// Verified to work with the Artifact Harvester
/datum/artifact_effect/stun
	name = "Stun"
	effect_color = "#00eeff"

/datum/artifact_effect/stun/New()
	..()
	effect_type = EFFECT_STUN

/datum/artifact_effect/stun/DoEffectTouch(mob/toucher)
	if(toucher && iscarbon(toucher))
		var/mob/living/carbon/C = toucher
		var/susceptibility = GetAnomalySusceptibility(C)
		if(prob(susceptibility * 100))
			to_chat(C, span_red("A powerful force overwhelms your consciousness."))
			C.status_at_least(EFFECT_WEAKENED, rand(1,10) * susceptibility)
			C.status_adjust(EFFECT_STUTTERING, 30 * susceptibility)
			C.status_at_least(EFFECT_STUNNED, rand(1,10) * susceptibility)

/datum/artifact_effect/stun/DoEffectAura()
	var/atom/holder = get_master_holder()
	if(holder)
		var/turf/T = get_turf(holder)
		for (var/mob/living/carbon/C in range(src.effectrange,T))
			var/susceptibility = GetAnomalySusceptibility(C)
			if(prob(10 * susceptibility))
				to_chat(C, span_red("Your body goes numb for a moment."))
				C.status_at_least(EFFECT_WEAKENED, 2)
				C.status_adjust(EFFECT_STUTTERING, 2)
				if(prob(10))
					C.status_at_least(EFFECT_STUNNED, 1)
			else if(prob(10))
				to_chat(C, span_red("You feel numb."))

/datum/artifact_effect/stun/DoEffectPulse()
	var/atom/holder = get_master_holder()
	if(holder)
		var/turf/T = get_turf(holder)
		for (var/mob/living/carbon/C in range(src.effectrange,T))
			var/susceptibility = GetAnomalySusceptibility(C)
			if(prob(100 * susceptibility))
				to_chat(C, span_red("A wave of energy overwhelms your senses!"))
				C.status_set(EFFECT_WEAKENED, 4 * susceptibility)
				C.status_set(EFFECT_STUTTERING, 4 * susceptibility)
				if(prob(10))
					C.status_set(EFFECT_STUNNED, 1 * susceptibility)
