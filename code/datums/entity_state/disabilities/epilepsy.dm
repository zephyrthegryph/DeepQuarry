/// Was /datum/component/epilepsy_disability: a trait-granted disability ticking once a Life cycle.
CAPABILITY_TYPE(epilepsy_disability, CAP_DISABILITY_EPILEPSY, /datum/capability/disability/epilepsy, key = NONE)
/datum/capability/disability/epilepsy

/datum/capability/disability/epilepsy/disability_tick(mob/living/owner)

	if(QDELETED(owner))
		return
	if(isbelly(owner.loc))
		return
	if(owner.stat != CONSCIOUS)
		return
	if(owner.transforming)
		return
	if((prob(1) && prob(1) && !owner.has_status(STAT_PARALYZED)))
		to_chat(owner, span_red("You have a seizure!"))
		for(var/mob/O in viewers(owner, null))
			if(O == owner)
				continue
			O.show_message(span_danger("[owner] starts having a seizure!"), 1)
		owner.status_at_least(STAT_PARALYZED, 10)
		owner.status_at_least(STAT_SLEEPING, 10)
		owner.status_adjust(STAT_JITTERY, 1000)
