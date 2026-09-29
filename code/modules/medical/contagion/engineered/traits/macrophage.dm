/*
//////////////////////////////////////

Macrophages

	Very noticeable.
	Lowers resistance slightly.
	Decreases stage speed.
	Increases transmittablity
	Fatal leve.

BONUS
	The virus grows and ceases to be microscopic.

//////////////////////////////////////
*/

/datum/viral_trait/macrophage
	name = "Macrophage"
	desc = "The virus grows within the host, ceasing to be microscopic and causing severe bodily harm. These Phages will seek out, attack, and infect more viable hosts."
	stealth = -4
	resistance = -1
	stage_speed = -2
	transmission = 2
	level = 9
	threat = 2
	symptom_delay_min = 40 SECONDS
	symptom_delay_max = 60 SECONDS

	var/gigagerms = FALSE
	var/netspeed = 0
	var/phagecounter = 10

	threshold_descs = list(
		"Stage Speed" = "The higher the stage speed, the more frequently will burst from the host.",
		"Resistance" = "The higher the resistance, the more health phages will have, and the more damage the will do.",
		"Transmission 10" = "Phages can be larger, and more aggressive.",
		"Transmission 12" = "Phages will carry all diseases within the host, instead of only containing their own."
	)

	prefixes = list("Ambulant ", "Macro")
	bodies = list("Phage")

/datum/viral_trait/macrophage/severityset(datum/affliction/contagion/engineered/A)
	. = ..()
	if(A.transmission >= 10)
		threat += 2

/datum/viral_trait/macrophage/Start(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	netspeed = max(1, A.stage_rate)
	if(A.transmission >= 10)
		gigagerms = TRUE

/datum/viral_trait/macrophage/Activate(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	var/mob/living/M = A.host
	switch(A.stage)
		if(1, 2, 3)
			if(prob(base_message_chance) && M.stat != DEAD)
				to_chat(M, span_notice("Your skin crawls."))
		if(4)
			if(prob(base_message_chance))
				act_message(M, null, MSG_SELF(span_userdanger("You cringe in pain as lumps form and move around on your skin!")), \
					MSG_OTHERS(span_danger("Lumps form on %U%'s skin!")))
		if(5)
			phagecounter -= max(2, A.stage_rate)
			if(gigagerms && phagecounter <= 0)
				Burst(A, M, TRUE)
				phagecounter += 10
			while(phagecounter <= 0)
				phagecounter += 5
				Burst(A, M)

/datum/viral_trait/macrophage/proc/Burst(datum/affliction/contagion/engineered/A, mob/living/M, gigagerms = FALSE)
	var/mob/living/simple_mob/vore/aggressive/macrophage/phage

	if(gigagerms)
		phage = new /mob/living/simple_mob/vore/aggressive/macrophage/giant(get_turf((M.loc)))
		phage.melee_damage_lower = rand(5, 10)
		phage.melee_damage_upper = rand(10, 15)
		M.injure(INJURY_CUT, rand(10, 20))
		M.emote("scream")
	else
		phage = new(get_turf((M.loc)))
		M.injure(INJURY_CUT, rand(1, 5))

	play_sfx(M, SFX_EFFECTS_SPLAT)

	phage.endurance += A.resistance
	// The creature carries detached copies, never the host's own affliction.
	var/datum/affliction/contagion/engineered/strain = A.Copy()
	phage.infections += strain
	phage.base_disease = strain

	if(A.transmission >= 12)
		for(var/datum/affliction/contagion/D in M.get_contagions())
			if((D.spread_flags & DISEASE_SPREAD_SPECIAL) || (D.spread_flags & DISEASE_SPREAD_CONTACT) || (D.spread_flags & DISEASE_SPREAD_FALTERED))
				continue
			if(D == A)
				continue
			phage.infections += D.Copy()
	act_message(M, null, MSG_SELF(span_userdanger("A slimy creature bursts forth from your flesh!")), \
		MSG_OTHERS(span_danger("A strange creature burst out of %U%!")))
	om_after(phage, 3 MINUTES, TYPE_PROC_REF(/mob/living/simple_mob/vore/aggressive/macrophage, deathcheck))
