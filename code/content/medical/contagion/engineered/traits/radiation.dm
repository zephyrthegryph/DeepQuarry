/datum/viral_trait/radiation
	name = "Irradiant Cells"
	desc = "Causes the cells in the host's body to give off harmful radiation."
	stealth = -1
	resistance = 2
	stage_speed = 1
	transmission = 2
	level = 7
	threat = 3
	symptom_delay_min = 10 SECONDS
	symptom_delay_max = 40 SECONDS
	threshold_descs = list(
		"Speed 8" = "Host takes radiation damage faster."
	)

	prefixes = list("Gamma ")
	bodies = list("Radiation")

/datum/viral_trait/radiation/severityset(datum/affliction/contagion/engineered/A)
	. = ..()
	if(A.stage_rate >= 8)
		threat += 1

/datum/viral_trait/radiation/Start(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	if(A.stage_rate >= 8)
		power = 2

/datum/viral_trait/radiation/Activate(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	var/mob/living/carbon/human/H = A.host
	if(H.stat == DEAD)
		return
	switch(A.stage)
		if(1)
			if(prob(10))
				to_chat(H, span_notice("You feel off..."))
		if(2, 3)
			if(prob(50))
				to_chat(H, span_danger("You feel like the atoms inside you are beginning to split..."))
		if(4, 5)
			radiate(H)

/datum/viral_trait/radiation/proc/radiate(mob/living/carbon/human/H)
	to_chat(H, span_danger("You feel a wave of pain throughout your body!"))
	H.add_radiation(50 * power)
	return TRUE
