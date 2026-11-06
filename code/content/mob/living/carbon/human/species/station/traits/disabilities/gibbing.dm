/// Was /datum/component/gibbing_disability: a trait-granted disability ticking once a Life cycle.
CAPABILITY_TYPE(gibbing_disability, CAP_DISABILITY_GIBBING, /datum/capability/disability/gibbing, key = NONE)
/datum/capability/disability/gibbing

/mob/living
	/// Gibbing disability: pressure built up so far (was the component's gutdeathpressure).
	/// Gibbing disability: 0 until the end starts, then counts the final emotes (was death_time).

/datum/capability/disability/gibbing/disability_tick(mob/living/owner)

	if(QDELETED(owner))
		return
	if(isbelly(owner.loc))
		return
	if(owner.transforming)
		return
	if(STATE_GET(owner, gut_disability, disability_death_time))
		if(STATE_GET(owner, gut_disability, disability_death_time) < 4)
			owner.emote(pick("whimper","belch","shiver"))
			STATE_SET(owner, gut_disability, disability_death_time, STATE_GET(owner, gut_disability, disability_death_time) + 1)
			return
		else
			owner.emote(pick("belch"))
			owner.gib()
			return
	STATE_SET(owner, gut_disability, disability_gut_pressure, STATE_GET(owner, gut_disability, disability_gut_pressure) + (0.01))
	if(STATE_GET(owner, gut_disability, disability_gut_pressure) > 0 && prob(STATE_GET(owner, gut_disability, disability_gut_pressure)))
		owner.emote(pick("whimper","belch","belch","belch","choke","shiver"))
		owner.status_at_least(STAT_WEAKENED, STATE_GET(owner, gut_disability, disability_gut_pressure) / 3)
	if((STATE_GET(owner, gut_disability, disability_gut_pressure)/3) >= 1 && prob(STATE_GET(owner, gut_disability, disability_gut_pressure)/3))
		STATE_SET(owner, gut_disability, disability_death_time, TRUE)
