/datum/viral_trait/viralreverse
	name = "Viral Aggressive Metabolism"
	desc = "The virus sacrifices its long term survivability to nearly instantly fully spread inside a host. \
	The virus will start at the last stage, but will eventually decay and die off by itself."
	stealth = 1
	resistance = 1
	stage_speed = 3
	transmission = -4
	level = 4
	symptom_delay_min = 1
	symptom_delay_max = 1
	threshold_descs = list(
		"Stage Speed" = "Highest between these determines the amount before self-curing.",
		"Stealth 4" = "Doubles the time before the virus self-cures."
	)

	var/time_to_cure

	prefixes = list("Spontaneous ")

/datum/viral_trait/viralreverse/Activate(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	if(time_to_cure > 0)
		time_to_cure--
	else
		var/mob/living/M = A.host
		Heal(M, A)

/datum/viral_trait/viralreverse/proc/Heal(mob/living/M, datum/affliction/contagion/engineered/A)
	A.set_stage(A.stage - 1)
	if(A.stage < 2)
		to_chat(M, span_notice("You suddenly feel healthy."))
		A.cure(FALSE)

/datum/viral_trait/viralreverse/Start(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	A.set_stage(5)
	if(A.stealth >= 4)
		power = 2
	time_to_cure = max(A.resistance, A.stage_rate) * 10 * power
