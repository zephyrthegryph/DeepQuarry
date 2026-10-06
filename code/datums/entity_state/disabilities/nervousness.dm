/// Was /datum/component/nervousness_disability: a trait-granted disability ticking once a Life cycle.
CAPABILITY_TYPE(nervousness_disability, CAP_DISABILITY_NERVOUSNESS, /datum/capability/disability/nervousness, key = NONE)
/datum/capability/disability/nervousness
	required_type = /mob/living/carbon/human

/datum/capability/disability/nervousness/disability_tick(mob/living/carbon/human/owner)

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
