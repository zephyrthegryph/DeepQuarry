// Slime mob proc overrides that route to slime_state instead of ai_holder.
//
// Replaces the bodies of the upstream slime mob procs that reached into the
// legacy ai_holder. After the legacy AI is deleted, ai_holder is gone, so
// these procs must read/write slime_state directly.

/mob/living/simple_mob/slime/xenobio/adjust_discipline(amount, silent)
	if(amount > 0)
		to_chat(src, span_warning("You've been disciplined!"))
	if(slime_state)
		slime_state.adjust_discipline(amount, silent)

/mob/living/simple_mob/slime/xenobio/is_justified_to_discipline()
	if(victim)
		if(ishuman(victim))
			var/mob/living/carbon/human/H = victim
			if(istype(H.species, /datum/species/monkey))
				return FALSE
		return TRUE
	if(slime_state)
		return slime_state.is_justified_to_discipline()
	return FALSE

/mob/living/simple_mob/slime/xenobio/enrage()
	if(harmless)
		return
	if(slime_state)
		slime_state.enrage()

/mob/living/simple_mob/slime/xenobio/relax()
	if(harmless)
		return
	if(slime_state)
		slime_state.relax()

/mob/living/simple_mob/slime/xenobio/pacify()
	harmless = TRUE
	if(slime_state)
		slime_state.pacify()
	faction = FACTION_NEUTRAL
	melee_damage_upper = 0
	melee_damage_lower = 0
	update_mood()

/mob/living/simple_mob/slime/xenobio/inherit_information(mob/living/simple_mob/slime/xenobio/predecessor)
	if(!predecessor || !predecessor.slime_state || !slime_state)
		return
	slime_state.discipline = max(predecessor.slime_state.discipline - 1, 0)
	slime_state.obedience = max(predecessor.slime_state.obedience - 1, 0)
	slime_state.resentment = max(predecessor.slime_state.resentment - 1, 0)
	slime_state.rabid = predecessor.slime_state.rabid

/mob/living/simple_mob/slime/xenobio/examine(mob/user)
	. = ..()
	if(slime_state)
		if(slime_state.rabid)
			. += "It seems very, very angry and upset."
		else if(slime_state.obedience >= 5)
			. += "It looks rather obedient."
		else if(slime_state.discipline)
			. += "It has been subjugated by force, at least for now."

/mob/living/simple_mob/slime/xenobio/update_mood()
	var/old_mood = mood
	var/pacified = FALSE
	var/obedient = 0
	if(incapacitated(INCAPACITATION_DISABLED))
		mood = "sad"
		pacified = TRUE
	else if(harmless)
		mood = ":33"
		pacified = TRUE
	else if(slime_state)
		if(slime_state.rabid)
			mood = "angry"
		else if(ai_brain?.primary_threat)
			mood = "mischevous"
		else if(slime_state.discipline)
			mood = "pout"
			pacified = TRUE
		else
			mood = ":3"
			pacified = TRUE
		obedient = slime_state.obedience
	else
		mood = ":3"
		pacified = TRUE
	if(obedient < 5)
		pacified = FALSE
	if(!client)
		if(faction != FACTION_SLIME)
			update_allowed_vore_types(TRUE)
		else if(old_mood == "angry")
			update_allowed_vore_types(FALSE, harmless)
		else
			update_allowed_vore_types(pacified, harmless)
	if(old_mood != mood)
		update_icon()

// Feral slime — also needs to know about discipline (just in case the AI is
// somehow checking it). Feral slimes don't have slime_state; they only need
// the discipline=0 path so existing checks work.

/mob/living/simple_mob/slime/feral
	use_modern_ai = TRUE

// Feral slimes inherit hostile defaults; brain handles combat. No discipline
// system on them — they always fight. The legacy feral.dm Initialize hooks
// already set up faction etc.
