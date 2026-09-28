/datum/tgui_module/agentcard
	name = "Agent Card"
	tgui_id = "AgentCard"

/datum/tgui_module/agentcard/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	var/obj/item/card/id/syndicate/S = tgui_host()
	if(!istype(S))
		return list()

	var/list/entries = list()
	entries += list(list("name" = "Age", 				"value" = S.age))
	entries += list(list("name" = "Appearance",			"value" = "Set"))
	entries += list(list("name" = "Assignment",			"value" = S.assignment))
	entries += list(list("name" = "Blood Type",			"value" = S.blood_type))
	entries += list(list("name" = "DNA Hash", 			"value" = S.dna_hash))
	entries += list(list("name" = "Fingerprint Hash",	"value" = S.fingerprint_hash))
	entries += list(list("name" = "Name", 				"value" = S.registered_name))
	entries += list(list("name" = "Photo", 				"value" = "Update"))
	entries += list(list("name" = "Sex", 				"value" = S.sex))
	entries += list(list("name" = "Species", 				"value" = S.species))
	entries += list(list("name" = "Factory Reset",		"value" = "Use With Care"))
	data["entries"] = entries

	data["electronic_warfare"] = S.electronic_warfare

	return data

/datum/tgui_module/agentcard/tgui_status(mob/user, datum/tgui_state/state)
	var/obj/item/card/id/syndicate/S = tgui_host()
	if(!istype(S))
		return STATUS_CLOSE
	if(user != S.registered_user())
		return STATUS_CLOSE
	return ..()

/datum/tgui_module/agentcard/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	var/obj/item/card/id/syndicate/S = tgui_host()
	switch(action)
		if("electronic_warfare")
			S.electronic_warfare = !S.electronic_warfare
			to_chat(ui.user, span_notice("Electronic warfare [S.electronic_warfare ? "enabled" : "disabled"]."))
			. = TRUE
		if("age")
			var/new_age = act_prompt(ui.user, action, params, ui, "a1", list("kind" = "number", "message" = "What age would you like to put on this card?", "title" = "Agent Card Age", "default" = S.age))
			if(isnull(new_age))
				return
			if(!isnull(new_age) && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
				if(new_age < 0)
					S.age = initial(S.age)
				else
					S.age = new_age
				to_chat(ui.user, span_notice("Age has been set to '[S.age]'."))
				. = TRUE
		if("appearance")
			var/datum/card_state/choice = act_prompt(ui.user, action, params, ui, "a2", list("kind" = "list", "message" = "Select the appearance for this card.", "title" = "Agent Card Appearance", "choices" = id_card_states()))
			if(isnull(choice))
				return
			if(choice && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
				S.icon_state = choice.icon_state
				S.item_state = choice.item_state
				S.sprite_stack = choice.sprite_stack
				S.update_icon()
				to_chat(ui.user, span_notice("Appearance changed to [choice]."))
				. = TRUE
		if("assignment")
			var/new_job = act_prompt(ui.user, action, params, ui, "a3", list("kind" = "text", "message" = "What assignment would you like to put on this card?\nChanging assignment will not grant or remove any access levels.", "title" = "Agent Card Assignment", "default" = S.assignment, "max_length" = MAX_MESSAGE_LEN))
			if(isnull(new_job))
				return
			if(!isnull(new_job) && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
				S.assignment = new_job
				to_chat(ui.user, span_notice("Occupation changed to '[new_job]'."))
				S.update_name()
				. = TRUE
		if("bloodtype")
			var/default = S.blood_type
			if(default == initial(S.blood_type) && ishuman(ui.user))
				var/mob/living/carbon/human/H = ui.user
				if(H.dna)
					default = H.dna.b_type
			var/new_blood_type = act_prompt(ui.user, action, params, ui, "a4", list("kind" = "text", "message" = "What blood type would you like to be written on this card?", "title" = "Agent Card Blood Type", "default" = default, "max_length" = MAX_MESSAGE_LEN))
			if(isnull(new_blood_type))
				return
			if(!isnull(new_blood_type) && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
				S.blood_type = new_blood_type
				to_chat(ui.user, span_notice("Blood type changed to '[new_blood_type]'."))
				. = TRUE
		if("dnahash")
			var/default = S.dna_hash
			if(default == initial(S.dna_hash) && ishuman(ui.user))
				var/mob/living/carbon/human/H = ui.user
				if(H.dna)
					default = H.dna.unique_enzymes
			var/new_dna_hash = act_prompt(ui.user, action, params, ui, "a5", list("kind" = "text", "message" = "What DNA hash would you like to be written on this card?", "title" = "Agent Card DNA Hash", "default" = default, "max_length" = MAX_MESSAGE_LEN))
			if(isnull(new_dna_hash))
				return
			if(!isnull(new_dna_hash) && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
				S.dna_hash = new_dna_hash
				to_chat(ui.user, span_notice("DNA hash changed to '[new_dna_hash]'."))
				. = TRUE
		if("fingerprinthash")
			var/default = S.fingerprint_hash
			if(default == initial(S.fingerprint_hash) && ishuman(ui.user))
				var/mob/living/carbon/human/H = ui.user
				if(H.dna)
					default = md5(H.dna.GetUniIdentity())
			var/new_fingerprint_hash = act_prompt(ui.user, action, params, ui, "a6", list("kind" = "text", "message" = "What fingerprint hash would you like to be written on this card?", "title" = "Agent Card Fingerprint Hash", "default" = default, "max_length" = MAX_MESSAGE_LEN))
			if(isnull(new_fingerprint_hash))
				return
			if(!isnull(new_fingerprint_hash) && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
				S.fingerprint_hash = new_fingerprint_hash
				to_chat(ui.user, span_notice("Fingerprint hash changed to '[new_fingerprint_hash]'."))
				. = TRUE
		if("name")
			var/_answer_a7 = act_prompt(ui.user, action, params, ui, "a7", list("kind" = "text", "message" = "What name would you like to put on this card?", "title" = "Agent Card Name", "default" = S.registered_name))
			if(isnull(_answer_a7))
				return
			var/new_name = sanitizeName(_answer_a7)
			if(!isnull(new_name) && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
				S.registered_name = new_name
				S.update_name()
				to_chat(ui.user, span_notice("Name changed to '[new_name]'."))
				. = TRUE
		if("photo")
			S.set_id_photo(ui.user)
			to_chat(ui.user, span_notice("Photo changed."))
			. = TRUE
		if("sex")
			var/new_sex = act_prompt(ui.user, action, params, ui, "a8", list("kind" = "text", "message" = "What sex would you like to put on this card?", "title" = "Agent Card Sex", "default" = S.sex, "max_length" = MAX_MESSAGE_LEN))
			if(isnull(new_sex))
				return
			if(!isnull(new_sex) && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
				S.sex = new_sex
				to_chat(ui.user, span_notice("Sex changed to '[new_sex]'."))
				. = TRUE
		if("species")
			var/new_species = act_prompt(ui.user, action, params, ui, "a9", list("kind" = "text", "message" = "What species would you like to put on this card?", "title" = "Agent Card Species", "default" = S.species, "max_length" = MAX_MESSAGE_LEN))
			if(isnull(new_species))
				return
			if(!isnull(new_species) && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
				S.species = new_species
				to_chat(ui.user, span_notice("Species changed to '[new_species]'."))
				. = TRUE
		if("factoryreset")
			var/_answer_a10 = act_prompt(ui.user, action, params, ui, "a10", list("message" = "This will factory reset the card, including access and owner. Continue?", "title" = "Factory Reset", "choices" = list("No", "Yes")))
			if(isnull(_answer_a10))
				return
			if(_answer_a10 == "Yes" && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
				S.age = initial(S.age)
				S.access = GLOB.syndicate_access.Copy()
				S.assignment = initial(S.assignment)
				S.blood_type = initial(S.blood_type)
				S.dna_hash = initial(S.dna_hash)
				S.electronic_warfare = initial(S.electronic_warfare)
				S.fingerprint_hash = initial(S.fingerprint_hash)
				S.icon_state = initial(S.icon_state)
				S.item_state = initial(S.item_state)
				S.sprite_stack = S.initial_sprite_stack
				S.front = null
				S.name = initial(S.name)
				S.registered_name = initial(S.registered_name)
				S.unset_registered_user()
				S.sex = initial(S.sex)
				S.species = initial(S.species)
				S.update_icon()
				to_chat(ui.user, span_notice("All information has been deleted from \the [src]."))
				. = TRUE
