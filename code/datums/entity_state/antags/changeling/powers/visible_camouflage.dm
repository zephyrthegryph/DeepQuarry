/datum/power/changeling/visible_camouflage
	name = "Camouflage"
	desc = "We rapidly shape the color of our skin and secrete easily reversible dye on our clothes, to blend in with our surroundings.  \
	We are undetectable, so long as we move slowly.(Toggle)"
	helptext = "Running, and performing most acts will reveal us.  Our chemical regeneration is halted while we are hidden."
	enhancedtext = "Can run while hidden."
	ability_icon_state = "ling_camoflage"
	genomecost = 3
	verbpath = /mob/proc/changeling_visible_camouflage

//Hide us from anyone who would do us harm.
/mob/proc/changeling_visible_camouflage()
	set category = VERB_CAT_CHANGELING
	set name = "Visible Camouflage (10)"
	set desc = "Turns yourself almost invisible, as long as you move slowly."
	var/datum/changeling/changeling = changeling_power(0,0,100,CONSCIOUS)
	if(!changeling)
		return

	if(ishuman(src))
		var/mob/living/carbon/human/H = src

		if(dq_get_cloaked(changeling))
			dq_set_cloaked(changeling, FALSE)
			return TRUE
		if(H.has_body_effect(/datum/body_effect/changeling_camouflage)) //If they double-clicked the button while invis.
			to_chat(H, span_warning("We are already camouflaged!"))
			return TRUE

		//We delay the check, so that people can uncloak without needing 10 chemicals to do so.
		changeling = changeling_power(10,0,100,CONSCIOUS)

		if(!changeling)
			return FALSE
		changeling.chem_charges -= 10

		to_chat(H, span_notice("We vanish from sight, and will remain hidden, so long as we move carefully."))
		dq_set_cloaked(changeling, TRUE)
		if(changeling.recursive_enhancement)
			to_chat(src, span_notice("We may move at our normal speed while hidden."))
			H.apply_body_effect(/datum/body_effect/changeling_camouflage/recursive, 0)
		else
			H.apply_body_effect(/datum/body_effect/changeling_camouflage, 0)

/datum/body_effect/changeling_camouflage
	stacks = MODIFIER_STACK_FORBID
	tick_interval = 2 SECONDS
	name = "Camoflauge"
	desc = "We are near-impossible to see."
	var/must_walk = TRUE
	// Per-application state: the changeling's chem recharge rate, suspended while camouflaged.


/datum/body_effect/changeling_camouflage/recursive
	must_walk = FALSE

/datum/body_effect/changeling_camouflage/can_apply(mob/living/L, suppress_failure = FALSE)
	return !!L.get_changeling_state()

/datum/body_effect/changeling_camouflage/on_start(mob/living/L)
	var/datum/changeling/comp = L.get_changeling_state()
	if(must_walk)
		L.set_m_intent(I_WALK)
	L.set_body_effect_state(type, comp.chem_recharge_rate)
	comp.chem_recharge_rate = 0
	animate(L,alpha = 255, alpha = 10, time = 10)

/datum/body_effect/changeling_camouflage/on_end(mob/living/L, expired)
	var/datum/changeling/comp = L.get_changeling_state()
	animate(L,alpha = 10, alpha = 255, time = 10)
	L.invisibility = initial(L.invisibility)
	act_message(L, null, MSG_SELF(span_notice("We revert our camouflage, revealing ourselves.")), \
		MSG_OTHERS(span_warning("%U% suddenly fades in, seemingly from nowhere!")))
	L.set_m_intent(I_RUN)
	if(comp)
		dq_set_cloaked(comp, FALSE)
		comp.chem_recharge_rate = L.body_effect_state(type) || 0

/datum/body_effect/changeling_camouflage/on_tick(mob/living/L)
	var/datum/changeling/comp = L.get_changeling_state()
	// Moving too fast, losing the cloak, being dead, unconscious or stunned uncloaks you.
	if(!comp || (L.m_intent != I_WALK && must_walk) || !dq_get_cloaked(comp) || L.stat || L.incapacitated(INCAPACITATION_DISABLED))
		L.end_body_effect(type, TRUE)
		return
	if(comp.chem_recharge_rate != 0) //Without this, there is an exploit that can be done, if one buys engorged chem sacks while cloaked.
		L.set_body_effect_state(type, (L.body_effect_state(type) || 0) + comp.chem_recharge_rate)
		comp.chem_recharge_rate = 0
