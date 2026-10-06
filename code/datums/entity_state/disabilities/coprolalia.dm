/// Was /datum/component/coprolalia_disability: a perk-granted disability ticking on the disabilities life stage.
/datum/om/behaviour/disability/coprolalia
	required_type = /mob/living/carbon/human

/datum/om/behaviour/disability/coprolalia/disability_tick(mob/living/carbon/human/owner)

	if(QDELETED(owner))
		return
	if(isbelly(owner.loc))
		return
	if(owner.stat != CONSCIOUS)
		return
	if(owner.transforming)
		return
	if(owner.client && (owner.client.prefs.muted & MUTE_IC))
		return
	if((prob(1) && prob(2) && owner.status_units(STAT_PARALYZED) <= 1))
		owner.status_at_least(STAT_STUNNED, 10)
		owner.status_adjust(STAT_JITTERY, 100)
		switch(rand(1, 3))
			if(1)
				owner.emote("twitch")
			if(2 to 3)
				owner.direct_say("[prob(50) ? ";" : ""][pick("SHIT", "PISS", "FUCK", "CUNT", "COCKSUCKER", "MOTHERFUCKER", "TITS")]")
