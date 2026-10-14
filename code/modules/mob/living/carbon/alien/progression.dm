/mob/living/carbon/alien/verb/evolve()

	set name = "Evolve"
	set desc = "Evolve into your adult form."
	set category = VERB_CAT_ABILITIES_GENERAL

	if(stat != CONSCIOUS)
		return

	if(!adult_form)
		grant(src, granted_verb(/mob/living/carbon/alien/verb/evolve, hidden = TRUE), src) // nothing to evolve into
		return

	if(get_equipped_item(SLOT_ID_HANDCUFFED) || get_equipped_item(SLOT_ID_LEGCUFFED))
		to_chat(src, span_red("You cannot evolve when you are cuffed."))
		return

	if(amount_grown < max_grown)
		to_chat(src, span_red("You are not fully grown."))
		return

	// confirm_evolution() handles choices and other specific requirements. A form that asks
	// the player returns null and calls evolve_into() when they answer.
	var/new_species = confirm_evolution()
	if(new_species)
		evolve_into(new_species)

/mob/living/carbon/alien/proc/evolve_into(new_species)
	if(!new_species || !adult_form || stat != CONSCIOUS)
		return

	var/mob/living/carbon/human/adult = new adult_form(get_turf(src))
	adult.set_species(new_species)
	show_evolution_blurb()

	transfer_languages(src, adult)

	if(src.faction != "neutral")
		adult.faction = src.faction

	if(move_player(src, adult, "grew into [adult]"))
		if (can_namepick_as_adult)
			// Until they answer (or if they cancel) they carry the default adult name.
			var/fallback = "[src.adult_name] ([instance_num])"
			adult.fully_replace_character_name(name, fallback)
			// The answer runs on the adult (src is deleted below), so the receiver is passed explicitly.
			open_request(adult, /datum/prompt/text, TYPE_PROC_REF(/mob/living/carbon/human, adult_name_chosen), answerer = adult, title = "Adult Name", question = "You have become an adult. Choose a name for yourself.", max_len = MAX_NAME_LEN, name_text = TRUE, timeout = 0)

	for (var/obj/item/W in contents_of(src))
		src.drop_from_inventory(W)

	for(var/datum/language/L in languages)
		adult.add_language(L.name)

	replaced_by(src, adult)

/mob/living/carbon/alien/proc/update_progression()
	if(amount_grown < max_grown)
		amount_grown++
	return

/mob/living/carbon/alien/proc/confirm_evolution()
	return

/mob/living/carbon/human/proc/adult_name_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/new_name = A.answer.value
	if(new_name)
		fully_replace_character_name(real_name, new_name)

/mob/living/carbon/alien/proc/show_evolution_blurb()
	return
