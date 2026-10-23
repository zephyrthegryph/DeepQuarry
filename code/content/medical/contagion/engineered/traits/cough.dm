/*
//////////////////////////////////////

Coughing

	Noticable.
	Little Resistance.
	Doesn't increase stage speed much.
	Transmittable.
	Low Level.

BONUS
	Will force the affected mob to drop small items. Small spread if not wearing a mask.

//////////////////////////////////////
*/

/datum/viral_trait/cough
	name = "Cough"
	desc = "The virus irritates the throat of the host, causing occasional coughing."
	stealth = -1
	resistance = 3
	stage_speed = 1
	transmission = 2
	level = 1
	threat = 0
	base_message_chance = 15
	symptom_delay_min = 15 SECONDS
	symptom_delay_max = 45 SECONDS

	var/infective = FALSE

	threshold_descs = list(
		"Resistance 3" = "Host will drop small items when coughing.",
		"Resistance 10" = "Occasionally causes coughing fits that stun the host.",
		"Stage Speed 6" = "Increases cough frequency",
		"Stealth 4" = "The symptom remains hidden until active.",
		"Transmission 11" = "The hosts coughing will occasionally spread the virus."
	)

	bodies = list("Cough")

/datum/viral_trait/cough/severityset(datum/affliction/contagion/engineered/A)
	. = ..()
	if(A.resistance >= 3)
		threat += 1
		if(A.resistance >= 10)
			threat += 1

/datum/viral_trait/cough/Start(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	if(A.stealth >= 4)
		supress_warning = TRUE
	if(A.resistance >= 3)
		power = 1.5
		if(A.resistance >= 10)
			power = 2
	if(A.stage_rate >= 6)
		symptom_delay_max = 10
	if(A.transmission >= 11)
		infective = TRUE

/datum/viral_trait/cough/Activate(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	var/mob/living/M = A.host
	if(M.stat == DEAD)
		return
	switch(A.stage)
		if(1 to 3)
			if(prob(base_message_chance) && !supress_warning)
				to_chat(M, span_warning(pick("Your throat itches.", "You lightly cough.")))
		else
			M.emote("cough")
			if(power >= 1.5)
				var/obj/item/I = M.get_active_hand()
				if(I && I.w_class == ITEMSIZE_COST_TINY)
					M.drop_item(get_turf(M))
			if(power >= 2 && prob(10))
				to_chat(M, span_userdanger(pick("You have a coughing fit!", "You can't stop coughing!")))
				M.status_at_least(STAT_STUNNED, 5)
				M.emote("cough")
				after(M, 1 SECONDS, TYPE_PROC_REF(/mob, emote), with = list("cough"))
				after(M, 3 SECONDS, TYPE_PROC_REF(/mob, emote), with = list("cough"))
				after(M, 6 SECONDS, TYPE_PROC_REF(/mob, emote), with = list("cough"))
			if(infective && !(A.spread_flags & DISEASE_SPREAD_FALTERED) && prob(50))
				after(A, 2 SECONDS, TYPE_PROC_REF(/datum/affliction/contagion, spread), with = list(2))
