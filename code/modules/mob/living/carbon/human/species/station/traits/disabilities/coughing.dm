/// Was /datum/component/coughing_disability: a trait-granted disability ticking once a Life cycle.
CAPABILITY_TYPE(coughing_disability, CAP_DISABILITY_COUGHING, /datum/capability/disability/coughing, key = NONE)
/datum/capability/disability/coughing
	var/cough_chance = 5

/datum/capability/disability/coughing/disability_tick(mob/living/owner)

	if(QDELETED(owner))
		return
	if(isbelly(owner.loc))
		return
	if(owner.stat != CONSCIOUS)
		return
	if(owner.transforming)
		return
	if((prob(cough_chance) && owner.status_units(STAT_PARALYZED) <= 1))
		owner.drop_item()
		owner.emote("cough")
