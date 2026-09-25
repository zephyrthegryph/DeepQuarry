/*
//////////////////////////////////////

Overactve Adrenal Gland

	No change to stealth.
	Slightly decreases resistance.
	Increases stage speed.
	Decreases transmittablity considerably.
	Moderate Level.

Bonus
	The host produces hyperzine and gets very jittery

//////////////////////////////////////
*/

/datum/symptom/stimulant
	name = "Hyperactivity"
	desc = "The virus causes restlessness, nervousness and hyperactivity, increasing the rate at which the host needs to eat, but making them harder to tire out"
	stealth = -4
	resistance = 0
	stage_speed = 2
	transmission = -3
	level = 8
	severity = 1
	symptom_delay_min = 25 SECONDS
	symptom_delay_max = 35 SECONDS

	var/clearacc = FALSE

	threshold_descs = list(
		"Resistance 8" = "This virus causes an even greater rate of nutriment loss, able to cause starvation, but it's energy gain greatly increases.",
		"Stage 8" = "The virus causes extreme nervousness and paranoia, resulting in occasional hallucinations, and extreme restlessness, but great overall energy."
	)

	prefixes = list("Gray ", "Amped ", "Nervous ")
	bodies = list("Hyper")

/datum/symptom/stimulant/severityset(datum/disease/advance/A)
	. = ..()
	if(A.resistance >= 8)
		severity -= 1
	if(A.stage_rate >= 8)
		severity -= 1
		prefixes = list("Gray ", "Amped ", "Paranoid ")
		suffixes = list(" Madness", " Insanity")

/datum/symptom/stimulant/Start(datum/disease/advance/A)
	if(!..())
		return
	power = initial(power)
	if(A.resistance >= 8)
		power += 2
	if(A.stage_rate >= 8)
		power += 1
		clearacc = TRUE

/datum/symptom/stimulant/Activate(datum/disease/advance/A)
	if(!..())
		return
	var/mob/living/carbon/human/H = A.affected_mob
	if(H.stat == DEAD)
		return
	switch(A.stage)
		if(2 to 3)
			if(prob(power) && !H.stat)
				H.status_adjust(EFFECT_JITTERY, 2 * power)
				H.emote("twitch")
				to_chat(H, span_notice("[pick("You feel energetic!", "You feel well-rested.", "You feel great!")]"))
		if(4 to 5)
			H.status_adjust(EFFECT_DROWSY, -(10 * power))
			H.status_adjust(EFFECT_SLEEPING, -10 * power)
			H.status_adjust(EFFECT_STUNNED, -10 * power)
			H.emote("twitch")
			H.reagents.add_reagent(REAGENT_ID_HYPERZINE, 5)
			if(prob(base_message_chance))
				to_chat(H, span_notice("[pick("You feel nervous...", "You feel anxious.", "You feel like everything is moving in slow motion.")]"))
			if(H.nutrition > 150 - (30 * power))
				H.nutrition = max(150 - (30 * power), H.nutrition - (2 * power))
			if(prob(25))
				H.status_adjust(EFFECT_JITTERY, 2 * power)
			if(clearacc)
				if(prob(power) && prob(50))
					H.emote("scream")
				H.status_set(EFFECT_HALLUCINATING, min(20, H.status_units(EFFECT_HALLUCINATING) + (5 * power)))
