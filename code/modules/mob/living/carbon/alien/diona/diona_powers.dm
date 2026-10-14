//Verbs after this point.
/mob/living/carbon/alien/diona/proc/merge()

	set category = VERB_CAT_ABILITIES_DIONA
	set name = "Merge with gestalt"
	set desc = "Merge with another diona."

	if(stat == DEAD || has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED) || has_status(STAT_STUNNED) || restrained())
		return

	if(istype(src.loc,/mob/living/carbon))
		revoke(src, granted_verb(/mob/living/carbon/alien/diona/proc/merge), src)
		return

	var/list/choices = list()
	for(var/mob/living/carbon/C in view(1,src))

		if(!(src.Adjacent(C)) || !(C.client)) continue

		if(ishuman(C))
			var/mob/living/carbon/human/D = C
			if(D.species && D.species.name == SPECIES_DIONA)
				choices += C

	if(!length(choices))
		to_chat(src, "There is nothing nearby to merge with.")
		return
	open_request(src, /datum/prompt/choice/diona_merge, PROC_REF(merge_target_chosen), answerer = src, choices = choices)

/// Re-checked on the answer: still conscious and not already merged into someone.
/datum/prompt/choice/diona_merge
	title = "Merge Choice"
	question = "Who do you wish to merge with?"
	ask_flags = ASK_CONSCIOUS
	timeout = 0

/datum/prompt/choice/diona_merge/recheck_extra()
	var/reason = ..()
	if(reason)
		return reason
	return istype(answerer.loc, /mob/living/carbon) ? "already merged" : null

/mob/living/carbon/alien/diona/proc/merge_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/M = A.answer.value
	if(QDELETED(M))
		return
	if(!do_merge(M))
		to_chat(src, "You fail to merge with \the [M]...")

/mob/living/carbon/alien/diona/proc/do_merge(mob/living/carbon/human/H)
	if(!istype(H) || !src || !(src.Adjacent(H)))
		return 0
	to_chat(H, "You feel your being twine with that of \the [src] as it merges with your biomass.")
	to_chat(src, "You feel your being twine with that of \the [H] as you merge with its biomass.")
	forceMove(H)
	grant(src, granted_verb(/mob/living/carbon/alien/diona/proc/split), src)
	revoke(src, granted_verb(/mob/living/carbon/alien/diona/proc/merge), src)
	return 1

/mob/living/carbon/alien/diona/proc/split()

	set category = VERB_CAT_ABILITIES_DIONA
	set name = "Split from gestalt"
	set desc = "Split away from your gestalt as a lone nymph."

	if(stat == DEAD || has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED) || has_status(STAT_STUNNED) || restrained())
		return

	if(!(istype(src.loc,/mob/living/carbon)))
		revoke(src, granted_verb(/mob/living/carbon/alien/diona/proc/split), src)
		return

	to_chat(src.loc, "You feel a pang of loss as [src] splits away from your biomass.")
	to_chat(src, "You wiggle out of the depths of [src.loc]'s biomass and plop to the ground.")

	var/mob/living/M = src.loc

	forceMove(get_turf(src))
	revoke(src, granted_verb(/mob/living/carbon/alien/diona/proc/split), src)
	grant(src, granted_verb(/mob/living/carbon/alien/diona/proc/merge), src)

	if(istype(M))
		for(var/atom/A in contents_of(M))
			if(istype(A,/mob/living/simple_mob/animal/borer) || istype(A,/obj/item/holder))
				return
