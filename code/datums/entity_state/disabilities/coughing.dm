/// Was /datum/component/coughing_disability: a perk-granted disability ticking on the disabilities life stage.
/datum/om/behaviour/disability/coughing
	var/cough_chance = 5

/datum/om/behaviour/disability/coughing/disability_tick(mob/living/owner)

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
