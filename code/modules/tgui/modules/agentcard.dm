/datum/tgui_module/agentcard
	name = "Agent Card"

CAPABILITIES(/datum/tgui_module/agentcard)
	interface("AgentCard")
	op("electronic_warfare", ui_act("electronic_warfare"), then(PROC_REF(ui_act_electronic_warfare)))
	op("age", ui_act("age"), then(PROC_REF(ui_act_age)))
	op("appearance", ui_act("appearance"), then(PROC_REF(ui_act_appearance)))
	op("assignment", ui_act("assignment"), then(PROC_REF(ui_act_assignment)))
	op("bloodtype", ui_act("bloodtype"), then(PROC_REF(ui_act_bloodtype)))
	op("dnahash", ui_act("dnahash"), then(PROC_REF(ui_act_dnahash)))
	op("fingerprinthash", ui_act("fingerprinthash"), then(PROC_REF(ui_act_fingerprinthash)))
	op("name", ui_act("name"), then(PROC_REF(ui_act_name)))
	op("photo", ui_act("photo"), then(PROC_REF(ui_act_photo)))
	op("sex", ui_act("sex"), then(PROC_REF(ui_act_sex)))
	op("species", ui_act("species"), then(PROC_REF(ui_act_species)))
	op("factoryreset", ui_act("factoryreset"), then(PROC_REF(ui_act_factoryreset)))

/datum/tgui_module/agentcard/ui_data(datum/act/eval/A)
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

/datum/tgui_module/agentcard/proc/ui_act_electronic_warfare(datum/act/op/A)
	var/obj/item/card/id/syndicate/S = tgui_host()
	S.electronic_warfare = !S.electronic_warfare
	to_chat(A.actor, span_notice("Electronic warfare [S.electronic_warfare ? "enabled" : "disabled"]."))
	return OP_OK

/datum/tgui_module/agentcard/proc/ui_act_age(datum/act/op/A)
	var/obj/item/card/id/syndicate/S = tgui_host()
	open_request(src, /datum/prompt/number, PROC_REF(age_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "What age would you like to put on this card?", title = "Agent Card Age", default = S.age, timeout = 0)

/datum/tgui_module/agentcard/proc/age_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_age = A.answer.value
	if(!isnull(new_age))
		if(new_age < 0)
			S.age = initial(S.age)
		else
			S.age = new_age
		to_chat(user, span_notice("Age has been set to '[S.age]'."))
		. = TRUE
	SStgui.update_uis(src)

/datum/tgui_module/agentcard/proc/ui_act_appearance(datum/act/op/A)
	open_request(src, /datum/prompt/choice, PROC_REF(appearance_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "Select the appearance for this card.", title = "Agent Card Appearance", choices = id_card_states(), timeout = 0)

/datum/tgui_module/agentcard/proc/appearance_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/datum/card_state/choice = A.answer.value
	if(choice)
		S.icon_state = choice.icon_state
		S.item_state = choice.item_state
		S.set_sprite_stack(choice.sprite_stack)
		to_chat(user, span_notice("Appearance changed to [choice]."))
		. = TRUE
	SStgui.update_uis(src)

/datum/tgui_module/agentcard/proc/ui_act_assignment(datum/act/op/A)
	var/obj/item/card/id/syndicate/S = tgui_host()
	open_request(src, /datum/prompt/text, PROC_REF(assignment_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "What assignment would you like to put on this card?\nChanging assignment will not grant or remove any access levels.", title = "Agent Card Assignment", default = S.assignment, timeout = 0)

/datum/tgui_module/agentcard/proc/assignment_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_job = A.answer.value
	if(!isnull(new_job))
		S.assignment = new_job
		to_chat(user, span_notice("Occupation changed to '[new_job]'."))
		S.update_name()
		. = TRUE
	SStgui.update_uis(src)

/datum/tgui_module/agentcard/proc/ui_act_bloodtype(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/default = S.blood_type
	if(default == initial(S.blood_type) && ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.dna)
			default = H.dna.b_type
	open_request(src, /datum/prompt/text, PROC_REF(bloodtype_answered), valid = PROC_REF(request_usable), answerer = user, question = "What blood type would you like to be written on this card?", title = "Agent Card Blood Type", default = default, timeout = 0)

/datum/tgui_module/agentcard/proc/bloodtype_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_blood_type = A.answer.value
	if(!isnull(new_blood_type))
		S.blood_type = new_blood_type
		to_chat(user, span_notice("Blood type changed to '[new_blood_type]'."))
		. = TRUE
	SStgui.update_uis(src)
/datum/tgui_module/agentcard/proc/ui_act_dnahash(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/default = S.dna_hash
	if(default == initial(S.dna_hash) && ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.dna)
			default = H.dna.unique_enzymes
	open_request(src, /datum/prompt/text, PROC_REF(dnahash_answered), valid = PROC_REF(request_usable), answerer = user, question = "What DNA hash would you like to be written on this card?", title = "Agent Card DNA Hash", default = default, timeout = 0)

/datum/tgui_module/agentcard/proc/dnahash_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_dna_hash = A.answer.value
	if(!isnull(new_dna_hash))
		S.dna_hash = new_dna_hash
		to_chat(user, span_notice("DNA hash changed to '[new_dna_hash]'."))
		. = TRUE
	SStgui.update_uis(src)
/datum/tgui_module/agentcard/proc/ui_act_fingerprinthash(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/default = S.fingerprint_hash
	if(default == initial(S.fingerprint_hash) && ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.dna)
			default = md5(H.dna.GetUniIdentity())
	open_request(src, /datum/prompt/text, PROC_REF(fingerprinthash_answered), valid = PROC_REF(request_usable), answerer = user, question = "What fingerprint hash would you like to be written on this card?", title = "Agent Card Fingerprint Hash", default = default, timeout = 0)

/datum/tgui_module/agentcard/proc/fingerprinthash_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_fingerprint_hash = A.answer.value
	if(!isnull(new_fingerprint_hash))
		S.fingerprint_hash = new_fingerprint_hash
		to_chat(user, span_notice("Fingerprint hash changed to '[new_fingerprint_hash]'."))
		. = TRUE
	SStgui.update_uis(src)
/datum/tgui_module/agentcard/proc/ui_act_name(datum/act/op/A)
	var/obj/item/card/id/syndicate/S = tgui_host()
	open_request(src, /datum/prompt/text, PROC_REF(name_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "What name would you like to put on this card?", title = "Agent Card Name", default = S.registered_name, timeout = 0)

/datum/tgui_module/agentcard/proc/name_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/_answer_a7 = A.answer.value
	var/new_name = sanitizeName(_answer_a7)
	if(!isnull(new_name))
		S.registered_name = new_name
		S.update_name()
		to_chat(user, span_notice("Name changed to '[new_name]'."))
		. = TRUE
	SStgui.update_uis(src)

/datum/tgui_module/agentcard/proc/ui_act_photo(datum/act/op/A)
	var/obj/item/card/id/syndicate/S = tgui_host()
	S.set_id_photo(A.actor)
	to_chat(A.actor, span_notice("Photo changed."))
	return OP_OK

/datum/tgui_module/agentcard/proc/ui_act_sex(datum/act/op/A)
	var/obj/item/card/id/syndicate/S = tgui_host()
	open_request(src, /datum/prompt/text, PROC_REF(sex_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "What sex would you like to put on this card?", title = "Agent Card Sex", default = S.sex, timeout = 0)

/datum/tgui_module/agentcard/proc/sex_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_sex = A.answer.value
	if(!isnull(new_sex))
		S.sex = new_sex
		to_chat(user, span_notice("Sex changed to '[new_sex]'."))
		. = TRUE
	SStgui.update_uis(src)

/datum/tgui_module/agentcard/proc/ui_act_species(datum/act/op/A)
	var/obj/item/card/id/syndicate/S = tgui_host()
	open_request(src, /datum/prompt/text, PROC_REF(species_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "What species would you like to put on this card?", title = "Agent Card Species", default = S.species, timeout = 0)

/datum/tgui_module/agentcard/proc/species_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_species = A.answer.value
	if(!isnull(new_species))
		S.species = new_species
		to_chat(user, span_notice("Species changed to '[new_species]'."))
		. = TRUE
	SStgui.update_uis(src)

/datum/tgui_module/agentcard/proc/ui_act_factoryreset(datum/act/op/A)
	open_request(src, /datum/prompt/yes_no, PROC_REF(factoryreset_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "This will factory reset the card, including access and owner. Continue?", title = "Factory Reset", timeout = 0)

/datum/tgui_module/agentcard/proc/factoryreset_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/_answer_a10 = (A.answer.value ? "Yes" : "No")
	if(_answer_a10 == "Yes")
		S.age = initial(S.age)
		S.access = GLOB.syndicate_access.Copy()
		S.assignment = initial(S.assignment)
		S.blood_type = initial(S.blood_type)
		S.dna_hash = initial(S.dna_hash)
		S.electronic_warfare = initial(S.electronic_warfare)
		S.fingerprint_hash = initial(S.fingerprint_hash)
		S.icon_state = initial(S.icon_state)
		S.item_state = initial(S.item_state)
		S.set_sprite_stack(S.initial_sprite_stack)
		S.front = null
		S.name = initial(S.name)
		S.registered_name = initial(S.registered_name)
		S.unset_registered_user()
		S.sex = initial(S.sex)
		S.species = initial(S.species)
		to_chat(user, span_notice("All information has been deleted from \the [src]."))
		. = TRUE
	SStgui.update_uis(src)
