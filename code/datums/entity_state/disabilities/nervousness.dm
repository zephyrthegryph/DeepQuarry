/// Was /datum/component/nervousness_disability: a perk-granted disability ticking on the disabilities life stage.
/datum/om/behaviour/disability/nervousness
	required_type = /mob/living/carbon/human

/datum/om/behaviour/disability/nervousness/disability_tick(mob/living/carbon/human/owner)

	if(QDELETED(owner))
		return
	if(isbelly(owner.loc))
		return
	if(owner.stat != CONSCIOUS)
		return
	if(owner.transforming)
		return
	if(prob(5) && prob(7))
		owner.status_at_least(STAT_STUTTERING, 15)
		if(owner.status_units(STAT_JITTERY) < 50)
			owner.status_adjust(STAT_JITTERY, 65)
