/datum/tgui_module/law_manager
	name = "Law manager"
	tgui_id = "LawManager"
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

UI_ACT(/datum/tgui_module/law_manager, "law_channel", ui_act_law_channel, UI_ARG_TEXT("law_channel"))
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_law_channel)
	if(params["law_channel"] in owner().law_channels())
		owner().lawchannel = params["law_channel"]
	return TRUE

UI_ACT(/datum/tgui_module/law_manager, "state_law", ui_act_state_law, UI_ARG_REF("ref", "proc:ui_source_owner_laws_all_laws", /datum/ai_law), UI_ARG_NUM("state_law"))
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_state_law)
	var/datum/ai_law/AL = params["ref"]
	if(AL)
		var/state_law = params["state_law"]
		owner().laws.set_state_law(AL, state_law)
	return TRUE

UI_ACT(/datum/tgui_module/law_manager, "add_zeroth_law", ui_act_add_zeroth_law)
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_add_zeroth_law)
	if(zeroth_law && is_admin(ui.user) && !owner().laws.zeroth_law)
		owner().set_zeroth_law(zeroth_law)
	return TRUE

UI_ACT(/datum/tgui_module/law_manager, "add_ion_law", ui_act_add_ion_law)
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_add_ion_law)
	if(ion_law && is_malf(ui.user))
		owner().add_ion_law(ion_law)
	return TRUE

UI_ACT(/datum/tgui_module/law_manager, "add_inherent_law", ui_act_add_inherent_law)
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_add_inherent_law)
	if(inherent_law && is_malf(ui.user))
		owner().add_inherent_law(inherent_law)
	return TRUE

UI_ACT(/datum/tgui_module/law_manager, "add_supplied_law", ui_act_add_supplied_law)
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_add_supplied_law)
	if(supplied_law && supplied_law_position >= 1 && supplied_law_position <= MAX_SUPPLIED_LAW_NUMBER && is_malf(ui.user))
		owner().add_supplied_law(supplied_law_position, supplied_law)
	return TRUE

UI_ACT(/datum/tgui_module/law_manager, "change_zeroth_law", ui_act_change_zeroth_law, UI_ARG_TEXT("val"))
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_change_zeroth_law)
	var/new_law = sanitize(params["val"])
	if(new_law && new_law != zeroth_law && can_still_topic(ui.user, state))
		zeroth_law = new_law
	return TRUE

UI_ACT(/datum/tgui_module/law_manager, "change_ion_law", ui_act_change_ion_law, UI_ARG_TEXT("val"))
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_change_ion_law)
	var/new_law = sanitize(params["val"])
	if(new_law && new_law != ion_law && can_still_topic(ui.user, state))
		ion_law = new_law
	return TRUE

UI_ACT(/datum/tgui_module/law_manager, "change_inherent_law", ui_act_change_inherent_law, UI_ARG_TEXT("val"))
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_change_inherent_law)
	var/new_law = sanitize(params["val"])
	if(new_law && new_law != inherent_law && can_still_topic(ui.user, state))
		inherent_law = new_law
	return TRUE

UI_ACT(/datum/tgui_module/law_manager, "change_supplied_law", ui_act_change_supplied_law, UI_ARG_TEXT("val"))
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_change_supplied_law)
	var/new_law = sanitize(params["val"])
	if(new_law && new_law != supplied_law && can_still_topic(ui.user, state))
		supplied_law = new_law
	return TRUE

UI_ACT(/datum/tgui_module/law_manager, "change_supplied_law_position", ui_act_change_supplied_law_position)
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_change_supplied_law_position)
	var/new_position = act_ask(ui.user, action, params, ui, "a1", /datum/om/prompt/number, message = "Enter new supplied law position between 1 and [MAX_SUPPLIED_LAW_NUMBER], inclusive. Inherent laws at the same index as a supplied law will not be stated.", title = "Law Position", default = supplied_law_position, max = MAX_SUPPLIED_LAW_NUMBER, min = 1)
	if(isnull(new_position))
		return
	if(isnum(new_position) && can_still_topic(ui.user, state))
		supplied_law_position = CLAMP(new_position, 1, MAX_SUPPLIED_LAW_NUMBER)
	return TRUE

UI_ACT(/datum/tgui_module/law_manager, "edit_law", ui_act_edit_law, UI_ARG_REF("edit_law", "proc:ui_source_owner_laws_all_laws", /datum/ai_law))
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_edit_law)
	if(is_malf(ui.user))
		var/datum/ai_law/AL = params["edit_law"]
		if(AL)
			var/new_law = act_ask(ui.user, action, params, ui, "a2", /datum/om/prompt/text, message = "Enter new law. Leaving the field blank will cancel the edit.", title = "Edit Law", default = AL.law)
			if(isnull(new_law))
				return
			if(new_law && new_law != AL.law && is_malf(ui.user) && can_still_topic(ui.user, state))
				log_and_message_admins("has changed a law of [owner()] from '[AL.law]' to '[new_law]'")
				AL.law = new_law
		return TRUE

UI_ACT(/datum/tgui_module/law_manager, "delete_law", ui_act_delete_law, UI_ARG_REF("delete_law", "proc:ui_source_owner_laws_all_laws", /datum/ai_law))
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_delete_law)
	if(is_malf(ui.user))
		var/datum/ai_law/AL = params["delete_law"]
		if(AL && is_malf(ui.user))
			owner().delete_law(AL)
	return TRUE

UI_ACT(/datum/tgui_module/law_manager, "state_laws", ui_act_state_laws)
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_state_laws)
	owner().statelaws(owner().laws)
	return TRUE

UI_ACT(/datum/tgui_module/law_manager, "state_law_set", ui_act_state_law_set, UI_ARG_REF("state_law_set", "proc:law_sets", /datum/ai_laws))
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_state_law_set)
	var/datum/ai_laws/ALs = params["state_law_set"]
	if(ALs && (is_admin(ui.user) || (ALs in GLOB.player_laws)))
		owner().statelaws(ALs)
	return TRUE

UI_ACT(/datum/tgui_module/law_manager, "transfer_laws", ui_act_transfer_laws, UI_ARG_REF("transfer_laws", "proc:law_sets", /datum/ai_laws))
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_transfer_laws)
	if(is_malf(ui.user))
		var/datum/ai_laws/ALs = params["transfer_laws"]
		if(ALs && (is_admin(ui.user) || (ALs in GLOB.player_laws)))
			log_and_message_admins("has transfered the [ALs.name] laws to [owner()].")
			ALs.sync(owner(), 0)
	return TRUE

UI_ACT(/datum/tgui_module/law_manager, "notify_laws", ui_act_notify_laws)
UI_ACT_PROC(/datum/tgui_module/law_manager, ui_act_notify_laws)
	to_chat(owner(), span_danger("Law Notice\n") + owner().laws.get_formatted_laws())
	if(isAI(owner()))
		var/mob/living/silicon/ai/AI = owner()
		for(var/mob/living/silicon/robot/R in AI.connected_robots)
			to_chat(R, span_danger("Law Notice\n") + R.laws.get_formatted_laws())
	if(ui.user != owner())
		to_chat(ui.user, span_notice("Laws displayed."))
	return TRUE

/// The list the UI_ARG_REF rows resolve refs in.
/datum/tgui_module/law_manager/proc/ui_source_owner_laws_all_laws()
	return owner().laws.all_laws()

/datum/tgui_module/law_manager/ui_prepare(mob/user, datum/tgui/ui)
	owner().lawsync()
	return ..()

UI_DATA(/datum/tgui_module/law_manager, "ion_law:text", "zeroth_law:text", "inherent_law:text", "supplied_law:text", "supplied_law_position", "merge:ui_data_datum_tgui_module_law_manager{ion_law_nr:unknown,isAI:num,isMalf:unknown,isSlaved:unknown,isAdmin:num,channel:unknown,channels:list,law_sets:unknown}")

/// The computed part of /datum/tgui_module/law_manager's window data (declared on its UI_DATA row).
/datum/tgui_module/law_manager/proc/ui_data_datum_tgui_module_law_manager(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["ion_law_nr"] = ionnum()

	package_laws(data, "zeroth_laws", list(owner().laws.zeroth_law))
	package_laws(data, "ion_laws", owner().laws.ion_laws)
	package_laws(data, "inherent_laws", owner().laws.inherent_laws)
	package_laws(data, "supplied_laws", owner().laws.supplied_laws)

	data["isAI"] = isAI(owner())
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
DECLARE_UI_STATE(/datum/tgui_module/law_manager/robot, GLOB.tgui_self_state)

/datum/tgui_module/law_manager/admin
DECLARE_UI_STATE(/datum/tgui_module/law_manager/admin, ADMIN_STATE(R_ADMIN|R_EVENT|R_DEBUG))

/datum/tgui_module/law_manager/admin/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		qdel(src)

/// The owner this refers to (a relation view: null once that is deleted).
/datum/tgui_module/law_manager/proc/owner() as /mob/living/silicon
	return owner
