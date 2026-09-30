/mob/living/silicon/ai/proc/show_laws_verb()
	set category = VERB_CAT_AI_COMMANDS
	set name = "Show Laws"
	src.show_laws()

/mob/living/silicon/ai/show_laws(everyone = 0)
	var/who

	if (everyone)
		who = world
	else
		who = src
		to_chat(who, span_filter_notice(span_bold("Obey these laws:")))

	src.laws_sanity_check()
	src.laws.show_laws(who)

/mob/living/silicon/ai/add_ion_law(law)
	..()
	for(var/mob/living/silicon/robot/R in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(R.lawupdate && (R.connected_ai == src))
			R.show_laws()

/mob/living/silicon/ai/proc/ai_checklaws()
	set category = VERB_CAT_AI_COMMANDS
	set name = "State Laws"
	subsystem_law_manager()
