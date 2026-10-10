CAPABILITIES(/datum/tgui_module/law_manager)
	op("state_laws", ui_act("state_laws"), then(PROC_REF(ui_act_state_laws)))
	op("notify_laws", ui_act("notify_laws"), then(PROC_REF(ui_act_notify_laws)))
	interface("LawManager")
	op("law_channel", ui_act("law_channel", arg("law_channel", schema_text(4096))), then(PROC_REF(ui_act_law_channel)))
	op("state_law", ui_act("state_law", arg("ref"), arg("state_law", num())), then(PROC_REF(ui_act_state_law)))
	op("add_zeroth_law", ui_act("add_zeroth_law"), then(PROC_REF(ui_act_add_zeroth_law)))
	op("add_ion_law", ui_act("add_ion_law"), then(PROC_REF(ui_act_add_ion_law)))
	op("add_inherent_law", ui_act("add_inherent_law"), then(PROC_REF(ui_act_add_inherent_law)))
	op("add_supplied_law", ui_act("add_supplied_law"), then(PROC_REF(ui_act_add_supplied_law)))
	op("change_zeroth_law", ui_act("change_zeroth_law", arg("val", schema_text(4096))), then(PROC_REF(ui_act_change_zeroth_law)))
	op("change_ion_law", ui_act("change_ion_law", arg("val", schema_text(4096))), then(PROC_REF(ui_act_change_ion_law)))
	op("change_inherent_law", ui_act("change_inherent_law", arg("val", schema_text(4096))), then(PROC_REF(ui_act_change_inherent_law)))
	op("change_supplied_law", ui_act("change_supplied_law", arg("val", schema_text(4096))), then(PROC_REF(ui_act_change_supplied_law)))
	op("change_supplied_law_position", ui_act("change_supplied_law_position"), then(PROC_REF(ui_act_change_supplied_law_position)))
	op("edit_law", ui_act("edit_law", arg("edit_law")), needs(req_bool(PROC_REF(ui_malf), silent = TRUE)), asks(/datum/prompt/text, fields = list("title" = "Edit Law", "question" = "Enter new law. Leaving the field blank will cancel the edit.", "default" = computed(PROC_REF(edit_law_default)))), then(PROC_REF(ui_act_edit_law)))
	op("delete_law", ui_act("delete_law", arg("delete_law")), then(PROC_REF(ui_act_delete_law)))
	op("state_law_set", ui_act("state_law_set", arg("state_law_set")), then(PROC_REF(ui_act_state_law_set)))
	op("transfer_laws", ui_act("transfer_laws", arg("transfer_laws")), then(PROC_REF(ui_act_transfer_laws)))

/datum/tgui_module/law_manager
	name = "Law manager"
	var/ion_law	= "IonLaw"
	var/zeroth_law = "ZerothLaw"
	var/inherent_law = "InherentLaw"
	var/supplied_law = "SuppliedLaw"
	var/supplied_law_position = MIN_SUPPLIED_LAW_NUMBER
	var/tmp/mob/living/silicon/owner

/datum/tgui_module/law_manager/New(mob/living/silicon/S)
	. = ..()

	rel_set(src, nameof(owner), S)

/// Every law set the UI may name; handlers check a non-admin picked a player set.
/datum/tgui_module/law_manager/proc/law_sets()
	return GLOB.admin_laws | GLOB.player_laws

/datum/tgui_module/law_manager/proc/ui_act_law_channel(datum/act/op/A, law_channel)
	if(law_channel in owner().law_channels())
		owner().lawchannel = law_channel
	return TRUE

/datum/tgui_module/law_manager/proc/ui_act_state_law(datum/act/op/A, ref, state_law_arg)
	var/datum/ai_law/AL = ui_ref(ref, ui_source_owner_laws_all_laws(), /datum/ai_law)
	if(AL)
		var/state_law = state_law_arg
		owner().laws.set_state_law(AL, state_law)
	return TRUE

/datum/tgui_module/law_manager/proc/ui_act_add_zeroth_law(datum/act/op/A)
	var/mob/user = A.actor
	if(zeroth_law && is_admin(user) && !owner().laws.zeroth_law)
		owner().set_zeroth_law(zeroth_law)
	return TRUE

/datum/tgui_module/law_manager/proc/ui_act_add_ion_law(datum/act/op/A)
	var/mob/user = A.actor
	if(ion_law && is_malf(user))
		owner().add_ion_law(ion_law)
	return TRUE

/datum/tgui_module/law_manager/proc/ui_act_add_inherent_law(datum/act/op/A)
	var/mob/user = A.actor
	if(inherent_law && is_malf(user))
		owner().add_inherent_law(inherent_law)
	return TRUE

/datum/tgui_module/law_manager/proc/ui_act_add_supplied_law(datum/act/op/A)
	var/mob/user = A.actor
	if(supplied_law && supplied_law_position >= 1 && supplied_law_position <= MAX_SUPPLIED_LAW_NUMBER && is_malf(user))
		owner().add_supplied_law(supplied_law_position, supplied_law)
	return TRUE

/datum/tgui_module/law_manager/proc/ui_act_change_zeroth_law(datum/act/op/A, val)
	var/new_law = sanitize(val)
	if(new_law && new_law != zeroth_law)
		zeroth_law = new_law
	return TRUE

/datum/tgui_module/law_manager/proc/ui_act_change_ion_law(datum/act/op/A, val)
	var/new_law = sanitize(val)
	if(new_law && new_law != ion_law)
		ion_law = new_law
	return TRUE

/datum/tgui_module/law_manager/proc/ui_act_change_inherent_law(datum/act/op/A, val)
	var/new_law = sanitize(val)
	if(new_law && new_law != inherent_law)
		inherent_law = new_law
	return TRUE

/datum/tgui_module/law_manager/proc/ui_act_change_supplied_law(datum/act/op/A, val)
	var/new_law = sanitize(val)
	if(new_law && new_law != supplied_law)
		supplied_law = new_law
	return TRUE

/datum/tgui_module/law_manager/proc/ui_act_change_supplied_law_position(datum/act/op/A)
	open_request(src, /datum/prompt/number, PROC_REF(change_supplied_law_position_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "Enter new supplied law position between 1 and [MAX_SUPPLIED_LAW_NUMBER], inclusive. Inherent laws at the same index as a supplied law will not be stated.", title = "Law Position", default = supplied_law_position, max_value = MAX_SUPPLIED_LAW_NUMBER, min_value = 1, timeout = 0)

/datum/tgui_module/law_manager/proc/change_supplied_law_position_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/new_position = A.answer.value
	if(isnum(new_position))
		supplied_law_position = CLAMP(new_position, 1, MAX_SUPPLIED_LAW_NUMBER)
	SStgui.update_uis(src)

/// Only an antagonist (or an admin on a silicon that is not slaved) edits or deletes laws; anyone else's button is not answered.
/datum/tgui_module/law_manager/proc/ui_malf(datum/act/op/A)
	return is_malf(A.actor)

/// The law the edit button names, when it is one of the owner's.
/datum/tgui_module/law_manager/proc/edited_law(datum/act/op/A)
	return ui_ref(A.args["edit_law"], ui_source_owner_laws_all_laws(), /datum/ai_law)

/datum/tgui_module/law_manager/proc/edit_law_default(datum/act/op/A)
	var/datum/ai_law/AL = edited_law(A)
	return AL?.law

/datum/tgui_module/law_manager/proc/ui_act_edit_law(datum/act/op/A, edit_law)
	var/datum/ai_law/AL = edited_law(A)
	var/datum/prompt/P = A.answer
	var/new_law = P?.value
	if(AL && new_law && new_law != AL.law && is_malf(A.actor))
		log_and_message_admins("has changed a law of [owner()] from '[AL.law]' to '[new_law]'")
		AL.law = new_law
	return TRUE

/datum/tgui_module/law_manager/proc/ui_act_delete_law(datum/act/op/A, delete_law)
	var/mob/user = A.actor
	if(is_malf(user))
		var/datum/ai_law/AL = ui_ref(delete_law, ui_source_owner_laws_all_laws(), /datum/ai_law)
		if(AL && is_malf(user))
			owner().delete_law(AL)
	return TRUE

/datum/tgui_module/law_manager/proc/ui_act_state_laws(datum/act/op/A)
	owner().statelaws(owner().laws)
	return OP_OK

/datum/tgui_module/law_manager/proc/ui_act_state_law_set(datum/act/op/A, state_law_set)
	var/mob/user = A.actor
	var/datum/ai_laws/ALs = ui_ref(state_law_set, law_sets(), /datum/ai_laws)
	if(ALs && (is_admin(user) || (ALs in GLOB.player_laws)))
		owner().statelaws(ALs)
	return TRUE

/datum/tgui_module/law_manager/proc/ui_act_transfer_laws(datum/act/op/A, transfer_laws)
	var/mob/user = A.actor
	if(is_malf(user))
		var/datum/ai_laws/ALs = ui_ref(transfer_laws, law_sets(), /datum/ai_laws)
		if(ALs && (is_admin(user) || (ALs in GLOB.player_laws)))
			log_and_message_admins("has transfered the [ALs.name] laws to [owner()].")
			ALs.sync(owner(), 0)
	return TRUE

/datum/tgui_module/law_manager/proc/ui_act_notify_laws(datum/act/op/A)
	to_chat(owner(), span_danger("Law Notice\n") + owner().laws.get_formatted_laws())
	var/mob/living/silicon/ai/AI = owner()
	if(istype(AI))
		for(var/mob/living/silicon/robot/R in AI.connected_robots)
			to_chat(R, span_danger("Law Notice\n") + R.laws.get_formatted_laws())
	if(A.actor != owner())
		to_chat(A.actor, span_notice("Laws displayed."))
	return OP_OK

/// The list the UI_ARG_REF rows resolve refs in.
/datum/tgui_module/law_manager/proc/ui_source_owner_laws_all_laws()
	return owner().laws.all_laws()

/datum/tgui_module/law_manager/ui_prepare(mob/user, datum/tgui/ui)
	owner().lawsync()
	return ..()

/datum/tgui_module/law_manager/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	data["ion_law"] = ion_law
	data["zeroth_law"] = zeroth_law
	data["inherent_law"] = inherent_law
	data["supplied_law"] = supplied_law
	data["supplied_law_position"] = supplied_law_position

	data["ion_law_nr"] = ionnum()

	package_laws(data, "zeroth_laws", list(owner().laws.zeroth_law))
	package_laws(data, "ion_laws", owner().laws.ion_laws)
	package_laws(data, "inherent_laws", owner().laws.inherent_laws)
	package_laws(data, "supplied_laws", owner().laws.supplied_laws)

	data["isAI"] = istype(owner(), /mob/living/silicon/ai)
	data["isMalf"] = is_malf(user)
	data["isSlaved"] = owner().is_slaved()
	data["isAdmin"] = is_admin(user)

	var/list/channels = list()
	for(var/ch_name in owner().law_channels())
		channels[++channels.len] = list("channel" = ch_name)
	data["channel"] = owner().lawchannel
	data["channels"] = channels
	data["law_sets"] = package_multiple_laws(data["isAdmin"] ? GLOB.admin_laws : GLOB.player_laws)

	return data

/datum/tgui_module/law_manager/proc/package_laws(list/data, field, list/datum/ai_law/laws)
	var/list/packaged_laws = list()
	for(var/datum/ai_law/AL in laws)
		packaged_laws[++packaged_laws.len] = list("law" = AL.law, "index" = AL.get_index(), "state" = owner().laws.get_state_law(AL), "ref" = "\ref[AL]")
	data[field] = packaged_laws
	data["has_[field]"] = packaged_laws.len

/datum/tgui_module/law_manager/proc/package_multiple_laws(list/datum/ai_laws/laws)
	var/list/law_sets = list()
	for(var/datum/ai_laws/ALs in laws)
		var/list/packaged_laws = list()
		package_laws(packaged_laws, "zeroth_laws", list(ALs.zeroth_law, ALs.zeroth_law_borg))
		package_laws(packaged_laws, "ion_laws", ALs.ion_laws)
		package_laws(packaged_laws, "inherent_laws", ALs.inherent_laws)
		package_laws(packaged_laws, "supplied_laws", ALs.supplied_laws)
		law_sets[++law_sets.len] = list("name" = ALs.name, "header" = ALs.law_header, "ref" = "\ref[ALs]","laws" = packaged_laws)

	return law_sets

/datum/tgui_module/law_manager/proc/is_malf(mob/user)
	return (is_admin(user) && !owner().is_slaved()) || is_special_role(user)

/datum/tgui_module/law_manager/proc/is_special_role(mob/user)
	if(user.mind && user.mind.special_role)
		return TRUE
	else
		return FALSE

/mob/living/silicon/proc/is_slaved()
	return 0

/mob/living/silicon/robot/is_slaved()
	return lawupdate && connected_ai ? sanitize(connected_ai.name) : null

/datum/tgui_module/law_manager/proc/sync_laws(mob/living/silicon/ai/AI)
	if(!AI)
		return
	for(var/mob/living/silicon/robot/R in AI.connected_robots)
		R.sync()
	log_and_message_admins("has syncronized [AI]'s laws with its borgs.")

/datum/tgui_module/law_manager/robot
CAPABILITIES(/datum/tgui_module/law_manager/robot)
	interface("LawManager", state = nameof(GLOB.tgui_self_state))

/datum/tgui_module/law_manager/admin
CAPABILITIES(/datum/tgui_module/law_manager/admin)
	interface("LawManager", rights = R_ADMIN|R_EVENT|R_DEBUG)

/datum/tgui_module/law_manager/admin/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		spent(src, user)

/// The owner this refers to (a relation view: null once that is deleted).
/datum/tgui_module/law_manager/proc/owner() as /mob/living/silicon
	return owner
