/datum/tgui_module/agentcard
	name = "Agent Card"

CAPABILITIES(/datum/tgui_module/agentcard)
	interface("AgentCard")
	op("electronic_warfare", ui_act("electronic_warfare"), then(PROC_REF(ui_act_electronic_warfare)))
	op("age", ui_act("age"), asks(/datum/prompt/number, fields = list("title" = "Agent Card Age", "question" = "What age would you like to put on this card?", "default" = computed(PROC_REF(age_default)), "timeout" = 0)), then(PROC_REF(ui_act_age)))
	op("appearance", ui_act("appearance"), asks(/datum/prompt/choice, fields = list("title" = "Agent Card Appearance", "question" = "Select the appearance for this card.", "choices" = computed(PROC_REF(appearance_choices)), "timeout" = 0)), then(PROC_REF(ui_act_appearance)))
	op("assignment", ui_act("assignment"), asks(/datum/prompt/text, fields = list("title" = "Agent Card Assignment", "question" = "What assignment would you like to put on this card?\nChanging assignment will not grant or remove any access levels.", "default" = computed(PROC_REF(assignment_default)), "timeout" = 0)), then(PROC_REF(ui_act_assignment)))
	op("bloodtype", ui_act("bloodtype"), asks(/datum/prompt/text, fields = list("title" = "Agent Card Blood Type", "question" = "What blood type would you like to be written on this card?", "default" = computed(PROC_REF(bloodtype_default)), "timeout" = 0)), then(PROC_REF(ui_act_bloodtype)))
	op("dnahash", ui_act("dnahash"), asks(/datum/prompt/text, fields = list("title" = "Agent Card DNA Hash", "question" = "What DNA hash would you like to be written on this card?", "default" = computed(PROC_REF(dnahash_default)), "timeout" = 0)), then(PROC_REF(ui_act_dnahash)))
	op("fingerprinthash", ui_act("fingerprinthash"), asks(/datum/prompt/text, fields = list("title" = "Agent Card Fingerprint Hash", "question" = "What fingerprint hash would you like to be written on this card?", "default" = computed(PROC_REF(fingerprinthash_default)), "timeout" = 0)), then(PROC_REF(ui_act_fingerprinthash)))
	op("name", ui_act("name"), asks(/datum/prompt/text, fields = list("title" = "Agent Card Name", "question" = "What name would you like to put on this card?", "default" = computed(PROC_REF(name_default)), "timeout" = 0)), then(PROC_REF(ui_act_name)))
	op("photo", ui_act("photo"), then(PROC_REF(ui_act_photo)))
	op("sex", ui_act("sex"), asks(/datum/prompt/text, fields = list("title" = "Agent Card Sex", "question" = "What sex would you like to put on this card?", "default" = computed(PROC_REF(sex_default)), "timeout" = 0)), then(PROC_REF(ui_act_sex)))
	op("species", ui_act("species"), asks(/datum/prompt/text, fields = list("title" = "Agent Card Species", "question" = "What species would you like to put on this card?", "default" = computed(PROC_REF(species_default)), "timeout" = 0)), then(PROC_REF(ui_act_species)))
	op("factoryreset", ui_act("factoryreset"), asks(/datum/prompt/yes_no, fields = list("title" = "Factory Reset", "question" = "This will factory reset the card, including access and owner. Continue?", "timeout" = 0)), then(PROC_REF(ui_act_factoryreset)))

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

/// What a field's question offers first: the card's own value, or (for the three hashes) the asker's own when the card still has the stock one.
/datum/tgui_module/agentcard/proc/age_default(datum/act/A)
	var/obj/item/card/id/syndicate/S = tgui_host()
	return S.age

/datum/tgui_module/agentcard/proc/appearance_choices(datum/act/A)
	return id_card_states()

/datum/tgui_module/agentcard/proc/assignment_default(datum/act/A)
	var/obj/item/card/id/syndicate/S = tgui_host()
	return S.assignment

/datum/tgui_module/agentcard/proc/bloodtype_default(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/default = S.blood_type
	if(default == initial(S.blood_type) && ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.dna)
			default = H.dna.b_type
	return default

/datum/tgui_module/agentcard/proc/dnahash_default(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/default = S.dna_hash
	if(default == initial(S.dna_hash) && ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.dna)
			default = H.dna.unique_enzymes
	return default

/datum/tgui_module/agentcard/proc/fingerprinthash_default(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/default = S.fingerprint_hash
	if(default == initial(S.fingerprint_hash) && ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.dna)
			default = md5(H.dna.GetUniIdentity())
	return default

/datum/tgui_module/agentcard/proc/name_default(datum/act/A)
	var/obj/item/card/id/syndicate/S = tgui_host()
	return S.registered_name

/datum/tgui_module/agentcard/proc/sex_default(datum/act/A)
	var/obj/item/card/id/syndicate/S = tgui_host()
	return S.sex

/datum/tgui_module/agentcard/proc/species_default(datum/act/A)
	var/obj/item/card/id/syndicate/S = tgui_host()
	return S.species

/datum/tgui_module/agentcard/proc/ui_act_age(datum/act/op/A)
	if(!A.answer)
		return OP_OK
	var/mob/user = A.actor
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_age = A.answer.value
	if(!isnull(new_age))
		if(new_age < 0)
			S.set_age(initial(S.age))
		else
			S.set_age(new_age)
		to_chat(user, span_notice("Age has been set to '[S.age]'."))
	return OP_OK

/datum/tgui_module/agentcard/proc/ui_act_appearance(datum/act/op/A)
	if(!A.answer)
		return OP_OK
	var/mob/user = A.actor
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/datum/card_state/choice = A.answer.value
	if(choice)
		S.set_icon_state(choice.icon_state)
		S.set_item_state(choice.item_state)
		S.set_sprite_stack(choice.sprite_stack)
		to_chat(user, span_notice("Appearance changed to [choice]."))
	return OP_OK

/datum/tgui_module/agentcard/proc/ui_act_assignment(datum/act/op/A)
	if(!A.answer)
		return OP_OK
	var/mob/user = A.actor
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_job = A.answer.value
	if(!isnull(new_job))
		S.set_assignment(new_job)
		to_chat(user, span_notice("Occupation changed to '[new_job]'."))
		S.update_name()
	return OP_OK

/datum/tgui_module/agentcard/proc/ui_act_bloodtype(datum/act/op/A)
	if(!A.answer)
		return OP_OK
	var/mob/user = A.actor
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_blood_type = A.answer.value
	if(!isnull(new_blood_type))
		S.set_blood_type(new_blood_type)
		to_chat(user, span_notice("Blood type changed to '[new_blood_type]'."))
	return OP_OK

/datum/tgui_module/agentcard/proc/ui_act_dnahash(datum/act/op/A)
	if(!A.answer)
		return OP_OK
	var/mob/user = A.actor
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_dna_hash = A.answer.value
	if(!isnull(new_dna_hash))
		S.set_dna_hash(new_dna_hash)
		to_chat(user, span_notice("DNA hash changed to '[new_dna_hash]'."))
	return OP_OK

/datum/tgui_module/agentcard/proc/ui_act_fingerprinthash(datum/act/op/A)
	if(!A.answer)
		return OP_OK
	var/mob/user = A.actor
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_fingerprint_hash = A.answer.value
	if(!isnull(new_fingerprint_hash))
		S.set_fingerprint_hash(new_fingerprint_hash)
		to_chat(user, span_notice("Fingerprint hash changed to '[new_fingerprint_hash]'."))
	return OP_OK

/datum/tgui_module/agentcard/proc/ui_act_name(datum/act/op/A)
	if(!A.answer)
		return OP_OK
	var/mob/user = A.actor
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_name = sanitizeName(A.answer.value)
	if(!isnull(new_name))
		S.set_registered_name(new_name)
		S.update_name()
		to_chat(user, span_notice("Name changed to '[new_name]'."))
	return OP_OK

/datum/tgui_module/agentcard/proc/ui_act_photo(datum/act/op/A)
	var/obj/item/card/id/syndicate/S = tgui_host()
	S.set_id_photo(A.actor)
	to_chat(A.actor, span_notice("Photo changed."))
	return OP_OK

/datum/tgui_module/agentcard/proc/ui_act_sex(datum/act/op/A)
	if(!A.answer)
		return OP_OK
	var/mob/user = A.actor
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_sex = A.answer.value
	if(!isnull(new_sex))
		S.set_sex(new_sex)
		to_chat(user, span_notice("Sex changed to '[new_sex]'."))
	return OP_OK

/datum/tgui_module/agentcard/proc/ui_act_species(datum/act/op/A)
	if(!A.answer)
		return OP_OK
	var/mob/user = A.actor
	var/obj/item/card/id/syndicate/S = tgui_host()
	var/new_species = A.answer.value
	if(!isnull(new_species))
		S.set_species(new_species)
		to_chat(user, span_notice("Species changed to '[new_species]'."))
	return OP_OK

/datum/tgui_module/agentcard/proc/ui_act_factoryreset(datum/act/op/A)
	if(!A.answer || !A.answer.value)
		return OP_OK
	var/mob/user = A.actor
	var/obj/item/card/id/syndicate/S = tgui_host()
	S.set_age(initial(S.age))
	S.set_access(GLOB.syndicate_access.Copy())
	S.set_assignment(initial(S.assignment))
	S.set_blood_type(initial(S.blood_type))
	S.set_dna_hash(initial(S.dna_hash))
	S.electronic_warfare = initial(S.electronic_warfare)
	S.set_fingerprint_hash(initial(S.fingerprint_hash))
	S.set_icon_state(initial(S.icon_state))
	S.set_item_state(initial(S.item_state))
	S.set_sprite_stack(S.initial_sprite_stack)
	S.set_front(null)
	S.name = initial(S.name)
	S.set_registered_name(initial(S.registered_name))
	S.unset_registered_user()
	S.set_sex(initial(S.sex))
	S.set_species(initial(S.species))
	to_chat(user, span_notice("All information has been deleted from \the [src]."))
	return OP_OK
