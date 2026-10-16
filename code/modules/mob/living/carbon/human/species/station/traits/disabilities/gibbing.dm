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
	if(sparse_get_or(owner, disability_death_time, 0))
		if(sparse_get_or(owner, disability_death_time, 0) < 4)
			owner.emote(pick("whimper","belch","shiver"))
			sparse_set_or(owner, disability_death_time, sparse_get_or(owner, disability_death_time, 0) + 1, 0)
			return
		else
			owner.emote(pick("belch"))
			owner.gib()
			return
	sparse_set_or(owner, disability_gut_pressure, sparse_get_or(owner, disability_gut_pressure, 0) + 0.01, 0)
	if(sparse_get_or(owner, disability_gut_pressure, 0) > 0 && prob(sparse_get_or(owner, disability_gut_pressure, 0)))
		owner.emote(pick("whimper","belch","belch","belch","choke","shiver"))
		owner.status_at_least(STAT_WEAKENED, sparse_get_or(owner, disability_gut_pressure, 0) / 3)
	if((sparse_get_or(owner, disability_gut_pressure, 0)/3) >= 1 && prob(sparse_get_or(owner, disability_gut_pressure, 0)/3))
		sparse_set_or(owner, disability_death_time, TRUE, 0)

sparse(/mob/living, disability_gut_pressure, type = num)

sparse(/mob/living, disability_death_time, type = num)
