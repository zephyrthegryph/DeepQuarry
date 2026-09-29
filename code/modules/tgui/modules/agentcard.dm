/datum/tgui_module/agentcard
	name = "Agent Card"
	tgui_id = "AgentCard"

UI_DATA(/datum/tgui_module/agentcard, "merge:ui_data_datum_tgui_module_agentcard{entries:list,electronic_warfare:num}")

/// The computed part of /datum/tgui_module/agentcard's window data (declared on its UI_DATA row).
/datum/tgui_module/agentcard/proc/ui_data_datum_tgui_module_agentcard(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

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

UI_ACT(/datum/tgui_module/agentcard, "electronic_warfare", ui_act_electronic_warfare)
UI_ACT_PROC(/datum/tgui_module/agentcard, ui_act_electronic_warfare)
	var/obj/item/card/id/syndicate/S = tgui_host()
	S.electronic_warfare = !S.electronic_warfare
	to_chat(ui.user, span_notice("Electronic warfare [S.electronic_warfare ? "enabled" : "disabled"]."))
	. = TRUE

UI_ACT(/datum/tgui_module/agentcard, "age", ui_act_age)
UI_ACT_PROC(/datum/tgui_module/agentcard, ui_act_age)
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_age = act_ask(ui.user, action, params, ui, "a1", /datum/om/prompt/number, message = "What age would you like to put on this card?", title = "Agent Card Age", default = S.age)
	if(isnull(new_age))
		return
	if(!isnull(new_age) && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
		if(new_age < 0)
			S.age = initial(S.age)
		else
			S.age = new_age
		to_chat(ui.user, span_notice("Age has been set to '[S.age]'."))
		. = TRUE

UI_ACT(/datum/tgui_module/agentcard, "appearance", ui_act_appearance)
UI_ACT_PROC(/datum/tgui_module/agentcard, ui_act_appearance)
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/datum/card_state/choice = act_ask(ui.user, action, params, ui, "a2", /datum/om/prompt/choice, message = "Select the appearance for this card.", title = "Agent Card Appearance", choices = id_card_states())
	if(isnull(choice))
		return
	if(choice && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
		S.icon_state = choice.icon_state
		S.item_state = choice.item_state
		S.sprite_stack = choice.sprite_stack
		S.update_icon()
		to_chat(ui.user, span_notice("Appearance changed to [choice]."))
		. = TRUE

UI_ACT(/datum/tgui_module/agentcard, "assignment", ui_act_assignment)
UI_ACT_PROC(/datum/tgui_module/agentcard, ui_act_assignment)
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_job = act_ask(ui.user, action, params, ui, "a3", /datum/om/prompt/text, message = "What assignment would you like to put on this card?\nChanging assignment will not grant or remove any access levels.", title = "Agent Card Assignment", default = S.assignment)
	if(isnull(new_job))
		return
	if(!isnull(new_job) && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
		S.assignment = new_job
		to_chat(ui.user, span_notice("Occupation changed to '[new_job]'."))
		S.update_name()
		. = TRUE

UI_ACT(/datum/tgui_module/agentcard, "bloodtype", ui_act_bloodtype)
UI_ACT_PROC(/datum/tgui_module/agentcard, ui_act_bloodtype)
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/default = S.blood_type
	if(default == initial(S.blood_type) && ishuman(ui.user))
		var/mob/living/carbon/human/H = ui.user
		if(H.dna)
			default = H.dna.b_type
	var/new_blood_type = act_ask(ui.user, action, params, ui, "a4", /datum/om/prompt/text, message = "What blood type would you like to be written on this card?", title = "Agent Card Blood Type", default = default)
	if(isnull(new_blood_type))
		return
	if(!isnull(new_blood_type) && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
		S.blood_type = new_blood_type
		to_chat(ui.user, span_notice("Blood type changed to '[new_blood_type]'."))
		. = TRUE

UI_ACT(/datum/tgui_module/agentcard, "dnahash", ui_act_dnahash)
UI_ACT_PROC(/datum/tgui_module/agentcard, ui_act_dnahash)
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/default = S.dna_hash
	if(default == initial(S.dna_hash) && ishuman(ui.user))
		var/mob/living/carbon/human/H = ui.user
		if(H.dna)
			default = H.dna.unique_enzymes
	var/new_dna_hash = act_ask(ui.user, action, params, ui, "a5", /datum/om/prompt/text, message = "What DNA hash would you like to be written on this card?", title = "Agent Card DNA Hash", default = default)
	if(isnull(new_dna_hash))
		return
	if(!isnull(new_dna_hash) && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
		S.dna_hash = new_dna_hash
		to_chat(ui.user, span_notice("DNA hash changed to '[new_dna_hash]'."))
		. = TRUE

UI_ACT(/datum/tgui_module/agentcard, "fingerprinthash", ui_act_fingerprinthash)
UI_ACT_PROC(/datum/tgui_module/agentcard, ui_act_fingerprinthash)
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/default = S.fingerprint_hash
	if(default == initial(S.fingerprint_hash) && ishuman(ui.user))
		var/mob/living/carbon/human/H = ui.user
		if(H.dna)
			default = md5(H.dna.GetUniIdentity())
	var/new_fingerprint_hash = act_ask(ui.user, action, params, ui, "a6", /datum/om/prompt/text, message = "What fingerprint hash would you like to be written on this card?", title = "Agent Card Fingerprint Hash", default = default)
	if(isnull(new_fingerprint_hash))
		return
	if(!isnull(new_fingerprint_hash) && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
		S.fingerprint_hash = new_fingerprint_hash
		to_chat(ui.user, span_notice("Fingerprint hash changed to '[new_fingerprint_hash]'."))
		. = TRUE

UI_ACT(/datum/tgui_module/agentcard, "name", ui_act_name)
UI_ACT_PROC(/datum/tgui_module/agentcard, ui_act_name)
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/_answer_a7 = act_ask(ui.user, action, params, ui, "a7", /datum/om/prompt/text, message = "What name would you like to put on this card?", title = "Agent Card Name", default = S.registered_name)
	if(isnull(_answer_a7))
		return
	var/new_name = sanitizeName(_answer_a7)
	if(!isnull(new_name) && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
		S.registered_name = new_name
		S.update_name()
		to_chat(ui.user, span_notice("Name changed to '[new_name]'."))
		. = TRUE

UI_ACT(/datum/tgui_module/agentcard, "photo", ui_act_photo)
UI_ACT_PROC(/datum/tgui_module/agentcard, ui_act_photo)
	var/obj/item/card/id/syndicate/S = tgui_host()
	S.set_id_photo(ui.user)
	to_chat(ui.user, span_notice("Photo changed."))
	. = TRUE

UI_ACT(/datum/tgui_module/agentcard, "sex", ui_act_sex)
UI_ACT_PROC(/datum/tgui_module/agentcard, ui_act_sex)
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_sex = act_ask(ui.user, action, params, ui, "a8", /datum/om/prompt/text, message = "What sex would you like to put on this card?", title = "Agent Card Sex", default = S.sex)
	if(isnull(new_sex))
		return
	if(!isnull(new_sex) && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
		S.sex = new_sex
		to_chat(ui.user, span_notice("Sex changed to '[new_sex]'."))
		. = TRUE

UI_ACT(/datum/tgui_module/agentcard, "species", ui_act_species)
UI_ACT_PROC(/datum/tgui_module/agentcard, ui_act_species)
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_species = act_ask(ui.user, action, params, ui, "a9", /datum/om/prompt/text, message = "What species would you like to put on this card?", title = "Agent Card Species", default = S.species)
	if(isnull(new_species))
		return
	if(!isnull(new_species) && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
		S.species = new_species
		to_chat(ui.user, span_notice("Species changed to '[new_species]'."))
		. = TRUE

UI_ACT(/datum/tgui_module/agentcard, "factoryreset", ui_act_factoryreset)
UI_ACT_PROC(/datum/tgui_module/agentcard, ui_act_factoryreset)
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/_answer_a10 = act_ask(ui.user, action, params, ui, "a10", /datum/om/prompt/choice/alert, message = "This will factory reset the card, including access and owner. Continue?", title = "Factory Reset", choices = list("No", "Yes"))
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
