//Verbs after this point.
/mob/living/carbon/alien/diona/proc/merge()

	set category = VERB_CAT_ABILITIES_DIONA
	set name = "Merge with gestalt"
	set desc = "Merge with another diona."

	if(stat == DEAD || has_status(EFFECT_PARALYZED) || has_status(EFFECT_WEAKENED) || has_status(EFFECT_STUNNED) || restrained())
		return

	if(istype(src.loc,/mob/living/carbon))
		remove_verb(src, /mob/living/carbon/alien/diona/proc/merge)
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
	om_ask(src, /datum/om/prompt/choice/diona_merge, PROC_REF(merge_target_chosen), choices = choices)

/// Re-checked on the answer: still conscious and not already merged into someone.
/datum/om/prompt/choice/diona_merge
	title = "Merge Choice"
	message = "Who do you wish to merge with?"
	ask_flags = ASK_CONSCIOUS

/datum/om/prompt/choice/diona_merge/valid()
	return istype(answerer.loc, /mob/living/carbon) ? "already merged" : null

/mob/living/carbon/alien/diona/proc/merge_target_chosen(datum/om/prompt/choice/diona_merge/ask)
	var/mob/living/M = ask.choice
	if(!do_merge(M))
		to_chat(src, "You fail to merge with \the [M]...")

/mob/living/carbon/alien/diona/proc/do_merge(mob/living/carbon/human/H)
	if(!istype(H) || !src || !(src.Adjacent(H)))
		return 0
	to_chat(H, "You feel your being twine with that of \the [src] as it merges with your biomass.")
	to_chat(src, "You feel your being twine with that of \the [H] as you merge with its biomass.")
	forceMove(H)
	add_verb(src, /mob/living/carbon/alien/diona/proc/split)
	remove_verb(src, /mob/living/carbon/alien/diona/proc/merge)
	return 1

/mob/living/carbon/alien/diona/proc/split()

	set category = VERB_CAT_ABILITIES_DIONA
	set name = "Split from gestalt"
	set desc = "Split away from your gestalt as a lone nymph."

	if(stat == DEAD || has_status(EFFECT_PARALYZED) || has_status(EFFECT_WEAKENED) || has_status(EFFECT_STUNNED) || restrained())
		return

	if(!(istype(src.loc,/mob/living/carbon)))
		remove_verb(src, /mob/living/carbon/alien/diona/proc/split)
		return

	to_chat(src.loc, "You feel a pang of loss as [src] splits away from your biomass.")
	to_chat(src, "You wiggle out of the depths of [src.loc]'s biomass and plop to the ground.")

	var/mob/living/M = src.loc

	forceMove(get_turf(src))
	remove_verb(src, /mob/living/carbon/alien/diona/proc/split)
	add_verb(src, /mob/living/carbon/alien/diona/proc/merge)

	if(istype(M))
		for(var/atom/A in contents_of(M))
			if(istype(A,/mob/living/simple_mob/animal/borer) || istype(A,/obj/item/holder))
				return
