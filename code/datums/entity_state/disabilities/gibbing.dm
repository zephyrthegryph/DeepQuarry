/// Was /datum/component/gibbing_disability: a perk-granted disability ticking on the disabilities life stage.
/datum/om/behaviour/disability/gibbing

/mob/living
	/// Gibbing disability: pressure built up so far (was the component's gutdeathpressure).
	var/disability_gut_pressure = 0
	/// Gibbing disability: 0 until the end starts, then counts the final emotes (was death_time).
	var/disability_death_time = FALSE

/datum/om/behaviour/disability/gibbing/disability_tick(mob/living/owner)

	if(QDELETED(owner))
		return
	if(isbelly(owner.loc))
		return
	if(owner.transforming)
		return
	if(owner.disability_death_time)
		if(owner.disability_death_time < 4)
			owner.emote(pick("whimper","belch","shiver"))
			owner.disability_death_time++
			return
		else
			owner.emote(pick("belch"))
			owner.gib()
			return
	owner.disability_gut_pressure += 0.01
	if(owner.disability_gut_pressure > 0 && prob(owner.disability_gut_pressure))
		owner.emote(pick("whimper","belch","belch","belch","choke","shiver"))
		owner.status_at_least(STAT_WEAKENED, owner.disability_gut_pressure / 3)
	if((owner.disability_gut_pressure/3) >= 1 && prob(owner.disability_gut_pressure/3))
		owner.disability_death_time = TRUE
