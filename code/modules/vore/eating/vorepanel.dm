//
// Vore management panel for players
//

#define STATION_PREF_NAME "Chomp"
#define VORE_BELLY_TAB 0
#define VORE_INSIDE_TAB 1
#define SOULCATCHER_TAB 2
#define GENERAL_TAB 3
#define PREFERENCE_TAB 4

/mob
	var/tmp/datum/vore_look/vorePanel

/mob/proc/insidePanel()
	set name = "Vore Panel"
	set category = VERB_CAT_IC_VORE

	if(SSticker.current_state == GAME_STATE_STARTUP)
		return

	if(!isliving(src))
		init_vore(TRUE)

	if(!vorePanel)
		if(!isnewplayer(src))
			log_vore("[src] ([type], \ref[src]) didn't have a vorePanel and tried to use the verb.")
		rel_set(src, nameof(vorePanel), new /datum/vore_look(src))

	vorePanel.tgui_interact(src)

/mob/proc/updateVRPanel() //Panel popup update call from belly events.
	if(vorePanel)
		SStgui.update_uis(vorePanel)

//
// Callback Handler for the Inside form
//
/datum/vore_look
	var/tmp/mob/host	// Note, we do this in case we ever want to allow people to view others vore panels
	var/unsaved_changes = FALSE
	var/show_pictures = TRUE
	var/icon_overflow = FALSE
	var/max_icon_content = 21 //Contents above this disable icon mode. 21 for nice 3 rows to fill the default panel window.
	var/active_tab = 0 // our current tab
	var/active_vore_tab = 0 // our vore sub tab
	var/message_option = 0 // our examine subtab
	var/message_subtab // our examine subtab
	var/sc_message_subtab // our soulcatcher message subtab
	var/aset_message_subtab
	var/selected_message
	var/list/preset_colors

/datum/vore_look/New(mob/new_host)
	if(istype(new_host))
		rel_set(src, nameof(host), new_host)
	. = ..()

/datum/vore_look/tgui_close(mob/user)
	if(user)
		user.write_preference_directly(/datum/preference/text/preset_colors, preset_colors)
	. = ..()

CAPABILITIES(/datum/vore_look)
	interface("VorePanel", title = "Vore Panel", state = nameof(GLOB.tgui_vorepanel_state))
	op("set_attribute", ui_act("set_attribute", arg("attribute", schema_text(4096)), arg("val"), arg("msgtype")), then(PROC_REF(ui_act_set_attribute)))
	op("liq_set_attribute", ui_act("liq_set_attribute", arg("attribute", schema_text(4096)), arg("val"), arg("msgtype")), then(PROC_REF(ui_act_liq_set_attribute)))
	op("change_tab", ui_act("change_tab", arg("tab", num())), then(PROC_REF(ui_act_change_tab)))
	op("change_vore_tab", ui_act("change_vore_tab", arg("tab", num())), then(PROC_REF(ui_act_change_vore_tab)))
	op("change_message_option", ui_act("change_message_option", arg("tab", num())), then(PROC_REF(ui_act_change_message_option)))
	op("change_message_type", ui_act("change_message_type", arg("tab", schema_text(4096))), then(PROC_REF(ui_act_change_message_type)))
	op("set_current_message", ui_act("set_current_message", arg("tab", schema_text(4096))), then(PROC_REF(ui_act_set_current_message)))
	op("change_sc_message_option", ui_act("change_sc_message_option", arg("tab", schema_text(4096))), then(PROC_REF(ui_act_change_sc_message_option)))
	op("change_aset_message_option", ui_act("change_aset_message_option", arg("tab", schema_text(4096))), then(PROC_REF(ui_act_change_aset_message_option)))
	op("show_pictures", ui_act("show_pictures"), then(PROC_REF(ui_act_show_pictures)))
	op("toggle_editmode_persistence", ui_act("toggle_editmode_persistence"), then(PROC_REF(ui_act_toggle_editmode_persistence)))
	op("newbelly", ui_act("newbelly", arg("val", schema_text(4096))), then(PROC_REF(ui_act_newbelly)))
	op("importpanel", ui_act("importpanel"), then(PROC_REF(ui_act_importpanel)))
	op("bellypick", ui_act("bellypick", arg("bellypick", schema_ref())), then(PROC_REF(ui_act_bellypick)))
	op("move_belly", ui_act("move_belly", arg("dir", num())), then(PROC_REF(ui_act_move_belly)))
	op("saveprefs", ui_act("saveprefs"), then(PROC_REF(ui_act_saveprefs)))
	op("reloadprefs", ui_act("reloadprefs"), asks(/datum/prompt/choice/vore_reload_preferences, fields = list("question" = "Are you sure you want to reload character slot preferences? This will remove your current vore organs and eject their contents.", "title" = "Confirmation", "choices" = list("Reload", "Cancel"), "buttons" = TRUE), step = "reload"), then(PROC_REF(ui_act_reloadprefs)))
	op("loadprefsfromslot", ui_act("loadprefsfromslot"), asks(/datum/prompt/choice/vore_load_preferences, fields = list("question" = "Are you sure you want to load another character slot's preferences? This will remove your current vore organs and eject their contents. This will not be immediately saved to your character slot, and you will need to save manually to overwrite your current bellies and preferences.", "title" = "Confirmation", "choices" = list("Load", "Cancel"), "buttons" = TRUE), step = "load"), then(PROC_REF(ui_act_loadprefsfromslot)))
	op("exportpanel", ui_act("exportpanel"), then(PROC_REF(ui_act_exportpanel)))
	op(TASTE_FLAVOR, ui_act(TASTE_FLAVOR, arg("val", schema_text(4096))), then(PROC_REF(ui_act_taste_flavor)))
	op(SMELL_FLAVOR, ui_act(SMELL_FLAVOR, arg("val", schema_text(4096))), then(PROC_REF(ui_act_smell_flavor)))
	op("toggle_dropnom_pred", ui_act("toggle_dropnom_pred"), then(PROC_REF(ui_act_toggle_dropnom_pred)))
	op("toggle_dropnom_prey", ui_act("toggle_dropnom_prey"), then(PROC_REF(ui_act_toggle_dropnom_prey)))
	op("toggle_afk_pred", ui_act("toggle_afk_pred"), then(PROC_REF(ui_act_toggle_afk_pred)))
	op("toggle_afk_prey", ui_act("toggle_afk_prey"), then(PROC_REF(ui_act_toggle_afk_prey)))
	op("toggle_latejoin_vore", ui_act("toggle_latejoin_vore"), then(PROC_REF(ui_act_toggle_latejoin_vore)))
	op("toggle_latejoin_prey", ui_act("toggle_latejoin_prey"), then(PROC_REF(ui_act_toggle_latejoin_prey)))
	op("toggle_allow_spontaneous_tf", ui_act("toggle_allow_spontaneous_tf"), then(PROC_REF(ui_act_toggle_allow_spontaneous_tf)))
	op("toggle_digest", ui_act("toggle_digest"), then(PROC_REF(ui_act_toggle_digest)))
	op("toggle_allowtemp", ui_act("toggle_allowtemp"), then(PROC_REF(ui_act_toggle_allowtemp)))
	op("toggle_global_privacy", ui_act("toggle_global_privacy"), then(PROC_REF(ui_act_toggle_global_privacy)))
	op("toggle_death_privacy", ui_act("toggle_death_privacy"), then(PROC_REF(ui_act_toggle_death_privacy)))
	op("toggle_mimicry", ui_act("toggle_mimicry"), then(PROC_REF(ui_act_toggle_mimicry)))
	op("toggle_devour", ui_act("toggle_devour"), then(PROC_REF(ui_act_toggle_devour)))
	op("toggle_resize", ui_act("toggle_resize"), then(PROC_REF(ui_act_toggle_resize)))
	op("toggle_feed", ui_act("toggle_feed"), then(PROC_REF(ui_act_toggle_feed)))
	op("toggle_absorbable", ui_act("toggle_absorbable"), then(PROC_REF(ui_act_toggle_absorbable)))
	op("toggle_leaveremains", ui_act("toggle_leaveremains"), then(PROC_REF(ui_act_toggle_leaveremains)))
	op("toggle_mobvore", ui_act("toggle_mobvore"), then(PROC_REF(ui_act_toggle_mobvore)))
	op("toggle_steppref", ui_act("toggle_steppref"), then(PROC_REF(ui_act_toggle_steppref)))
	op("toggle_pickuppref", ui_act("toggle_pickuppref"), then(PROC_REF(ui_act_toggle_pickuppref)))
	op("toggle_strippref", ui_act("toggle_strippref"), then(PROC_REF(ui_act_toggle_strippref)))
	op("toggle_contaminate_pref", ui_act("toggle_contaminate_pref"), then(PROC_REF(ui_act_toggle_contaminate_pref)))
	op("toggle_allow_mind_transfer", ui_act("toggle_allow_mind_transfer"), then(PROC_REF(ui_act_toggle_allow_mind_transfer)))
	op("toggle_healbelly", ui_act("toggle_healbelly"), then(PROC_REF(ui_act_toggle_healbelly)))
	op("toggle_fx", ui_act("toggle_fx"), then(PROC_REF(ui_act_toggle_fx)))
	op("toggle_noisy", ui_act("toggle_noisy"), then(PROC_REF(ui_act_toggle_noisy)))
	op("set_max_voreoverlay_alpha", ui_act("set_max_voreoverlay_alpha", arg("val", num())), then(PROC_REF(ui_act_set_max_voreoverlay_alpha)))
	op("toggle_liq_rec", ui_act("toggle_liq_rec"), then(PROC_REF(ui_act_toggle_liq_rec)))
	op("toggle_liq_giv", ui_act("toggle_liq_giv"), then(PROC_REF(ui_act_toggle_liq_giv)))
	op("toggle_liq_apply", ui_act("toggle_liq_apply"), then(PROC_REF(ui_act_toggle_liq_apply)))
	op("toggle_autotransferable", ui_act("toggle_autotransferable"), then(PROC_REF(ui_act_toggle_autotransferable)))
	op("toggle_noisy_full", ui_act("toggle_noisy_full"), then(PROC_REF(ui_act_toggle_noisy_full)))
	op("toggle_drop_vore", ui_act("toggle_drop_vore"), then(PROC_REF(ui_act_toggle_drop_vore)))
	op("toggle_slip_vore", ui_act("toggle_slip_vore"), then(PROC_REF(ui_act_toggle_slip_vore)))
	op("toggle_stumble_vore", ui_act("toggle_stumble_vore"), then(PROC_REF(ui_act_toggle_stumble_vore)))
	op("toggle_throw_vore", ui_act("toggle_throw_vore"), then(PROC_REF(ui_act_toggle_throw_vore)))
	op("toggle_phase_vore", ui_act("toggle_phase_vore"), then(PROC_REF(ui_act_toggle_phase_vore)))
	op("toggle_food_vore", ui_act("toggle_food_vore"), then(PROC_REF(ui_act_toggle_food_vore)))
	op("toggle_consume_liquid_belly", ui_act("toggle_consume_liquid_belly"), then(PROC_REF(ui_act_toggle_consume_liquid_belly)))
	op("toggle_digest_pain", ui_act("toggle_digest_pain"), then(PROC_REF(ui_act_toggle_digest_pain)))
	op("switch_selective_mode_pref", ui_act("switch_selective_mode_pref", arg("val")), then(PROC_REF(ui_act_switch_selective_mode_pref)))
	op("switch_strip_mode_pref", ui_act("switch_strip_mode_pref", arg("val", num())), then(PROC_REF(ui_act_switch_strip_mode_pref)))
	op("toggle_nutrition_ex", ui_act("toggle_nutrition_ex"), then(PROC_REF(ui_act_toggle_nutrition_ex)))
	op("toggle_weight_ex", ui_act("toggle_weight_ex"), then(PROC_REF(ui_act_toggle_weight_ex)))
	op("set_vs_color", ui_act("set_vs_color", arg("attribute", schema_text(4096)), arg("val", schema_text(4096))), then(PROC_REF(ui_act_set_vs_color)))
	op("toggle_vs_multiply", ui_act("toggle_vs_multiply", arg("attribute", schema_text(4096))), then(PROC_REF(ui_act_toggle_vs_multiply)))
	op("set_belly_rub", ui_act("set_belly_rub", arg("val", schema_text(4096))), then(PROC_REF(ui_act_set_belly_rub)))
	op("toggle_no_latejoin_vore_warning", ui_act("toggle_no_latejoin_vore_warning"), then(PROC_REF(ui_act_toggle_no_latejoin_vore_warning)))
	op("toggle_no_latejoin_prey_warning", ui_act("toggle_no_latejoin_prey_warning"), then(PROC_REF(ui_act_toggle_no_latejoin_prey_warning)))
	op("adjust_no_latejoin_vore_warning_time", ui_act("adjust_no_latejoin_vore_warning_time", arg("new_pred_time", num())), then(PROC_REF(ui_act_adjust_no_latejoin_vore_warning_time)))
	op("adjust_no_latejoin_prey_warning_time", ui_act("adjust_no_latejoin_prey_warning_time", arg("new_prey_time", num())), then(PROC_REF(ui_act_adjust_no_latejoin_prey_warning_time)))
	op("toggle_no_latejoin_vore_warning_persists", ui_act("toggle_no_latejoin_vore_warning_persists"), then(PROC_REF(ui_act_toggle_no_latejoin_vore_warning_persists)))
	op("toggle_no_latejoin_prey_warning_persists", ui_act("toggle_no_latejoin_prey_warning_persists"), then(PROC_REF(ui_act_toggle_no_latejoin_prey_warning_persists)))
	op("toggle_soulcatcher_allow_capture", ui_act("toggle_soulcatcher_allow_capture"), then(PROC_REF(ui_act_toggle_soulcatcher_allow_capture)))
	op("toggle_soulcatcher_allow_transfer", ui_act("toggle_soulcatcher_allow_transfer"), then(PROC_REF(ui_act_toggle_soulcatcher_allow_transfer)))
	op("toggle_soulcatcher_allow_takeover", ui_act("toggle_soulcatcher_allow_takeover"), then(PROC_REF(ui_act_toggle_soulcatcher_allow_takeover)))
	op("toggle_soulcatcher_allow_deletion", ui_act("toggle_soulcatcher_allow_deletion"), then(PROC_REF(ui_act_toggle_soulcatcher_allow_deletion)))
	op("adjust_own_size", ui_act("adjust_own_size", arg("new_mob_size", num())), then(PROC_REF(ui_act_adjust_own_size)))
	op("soulcatcher_release_all", ui_act("soulcatcher_release_all"), then(PROC_REF(ui_act_soulcatcher_release_all)))
	op("soulcatcher_erase_all", ui_act("soulcatcher_erase_all"), then(PROC_REF(ui_act_soulcatcher_erase_all)))
	op("soulcatcher_release", ui_act("soulcatcher_release"), then(PROC_REF(ui_act_soulcatcher_release)))
	op("soulcatcher_transfer", ui_act("soulcatcher_transfer"), then(PROC_REF(ui_act_soulcatcher_transfer)))
	op("soulcatcher_delete", ui_act("soulcatcher_delete"), then(PROC_REF(ui_act_soulcatcher_delete)))
	op("soulcatcher_transfer_control", ui_act("soulcatcher_transfer_control"), then(PROC_REF(ui_act_soulcatcher_transfer_control)))
	op("soulcatcher_release_control", ui_act("soulcatcher_release_control"), then(PROC_REF(ui_act_soulcatcher_release_control)))
	op("soulcatcher_select", ui_act("soulcatcher_select", arg("selected_soul", schema_ref())), then(PROC_REF(ui_act_soulcatcher_select)))
	op("soulcatcher_toggle", ui_act("soulcatcher_toggle"), then(PROC_REF(ui_act_soulcatcher_toggle)))
	op("soulcatcher_sfx", ui_act("soulcatcher_sfx", arg("val", schema_ref(/obj))), then(PROC_REF(ui_act_soulcatcher_sfx)))
	op("toggle_self_catching", ui_act("toggle_self_catching"), then(PROC_REF(ui_act_toggle_self_catching)))
	op("toggle_prey_catching", ui_act("toggle_prey_catching"), then(PROC_REF(ui_act_toggle_prey_catching)))
	op("toggle_drain_catching", ui_act("toggle_drain_catching"), then(PROC_REF(ui_act_toggle_drain_catching)))
	op("toggle_ghost_catching", ui_act("toggle_ghost_catching"), then(PROC_REF(ui_act_toggle_ghost_catching)))
	op("toggle_ext_hearing", ui_act("toggle_ext_hearing"), then(PROC_REF(ui_act_toggle_ext_hearing)))
	op("toggle_ext_vision", ui_act("toggle_ext_vision"), then(PROC_REF(ui_act_toggle_ext_vision)))
	op("toggle_mind_backup", ui_act("toggle_mind_backup"), then(PROC_REF(ui_act_toggle_mind_backup)))
	op("toggle_sr_projecting", ui_act("toggle_sr_projecting"), then(PROC_REF(ui_act_toggle_sr_projecting)))
	op("toggle_vore_sfx", ui_act("toggle_vore_sfx"), then(PROC_REF(ui_act_toggle_vore_sfx)))
	op("toggle_sr_vision", ui_act("toggle_sr_vision"), then(PROC_REF(ui_act_toggle_sr_vision)))
	op("soulcatcher_rename", ui_act("soulcatcher_rename", arg("val", schema_text(4096))), then(PROC_REF(ui_act_soulcatcher_rename)))
	op(SC_INTERIOR_MESSAGE, ui_act(SC_INTERIOR_MESSAGE, arg("val")), then(PROC_REF(ui_act_sc_interior_message)))
	op(SC_CAPTURE_MEESAGE, ui_act(SC_CAPTURE_MEESAGE, arg("val")), then(PROC_REF(ui_act_sc_capture_meesage)))
	op(SC_TRANSIT_MESSAGE, ui_act(SC_TRANSIT_MESSAGE, arg("val")), then(PROC_REF(ui_act_sc_transit_message)))
	op(SC_RELEASE_MESSAGE, ui_act(SC_RELEASE_MESSAGE, arg("val")), then(PROC_REF(ui_act_sc_release_message)))
	op(SC_TRANSFERE_MESSAGE, ui_act(SC_TRANSFERE_MESSAGE, arg("val")), then(PROC_REF(ui_act_sc_transfere_message)))
	op(SC_DELETE_MESSAGE, ui_act(SC_DELETE_MESSAGE, arg("val")), then(PROC_REF(ui_act_sc_delete_message)))
	op("preset", ui_act("preset", arg("color", schema_text(4096)), arg("index", num())), then(PROC_REF(ui_act_preset)))
	op("pick_from_inside", ui_act("pick_from_inside", arg("pick", schema_ref(/atom/movable)), arg("belly", schema_ref(/obj/belly)), arg("option", schema_text(64))), then(PROC_REF(ui_act_pick_from_inside)))
	op("pick_from_outside", ui_act("pick_from_outside", arg("pickall", bool()), arg("intent", schema_text(64)), arg("val", schema_ref(/obj/belly)), arg("pick", schema_ref(/atom/movable)), arg("option", schema_text(64)), arg("targetBelly", schema_ref(/obj/belly))), then(PROC_REF(ui_act_pick_from_outside)))
	op("prey_ability", ui_act("prey_ability", arg("belly", schema_ref(/obj/belly)), arg("ability", schema_text(64))), then(PROC_REF(perform_prey_ability)))
	op("set_spont_belly", ui_act("set_spont_belly", arg("attribute", schema_text(64)), arg("val", schema_text(MAX_NAME_LEN))), then(PROC_REF(set_spont_belly)))

// This looks weird, but all tgui_host is used for is state checking
// So this allows us to use the self_state just fine.
/datum/vore_look/tgui_host(mob/user)
	return host()

// Note, in order to allow others to look at others vore panels, this state would need
// to be modified.

/datum/vore_look/var/static/list/nom_icons
/datum/vore_look/proc/cached_nom_icon(atom/target)
	LAZYINITLIST(nom_icons)

	var/key = ""
	if(isobj(target))
		key = "[target.type]"
	else if(ismob(target))
		var/mob/M = target
		if(istype(M,/mob/living/simple_mob)) //not generating unique icons for every simplemob(number)
			var/mob/living/simple_mob/S = M
			key = "[S.icon_living]"
		else
			key = "\ref[target][M.real_name]"
	if(nom_icons[key])
		. = nom_icons[key]
	else
		. = icon2base64(getFlatIcon(target,defdir=SOUTH,no_anim=TRUE))
		nom_icons[key] = .

/datum/vore_look/tgui_static_data(mob/user)
	var/list/data = ..()

	data["vore_words"] = list(
		"%goo" = GLOB.vore_words_goo,
		"%happybelly" = GLOB.vore_words_hbellynoises,
		"%fat" = GLOB.vore_words_fat,
		"%grip" = GLOB.vore_words_grip,
		"%cozy" = GLOB.vore_words_cozyholdingwords,
		"%angry" = GLOB.vore_words_angry,
		"%acid" = GLOB.vore_words_acid,
		"%snack" = GLOB.vore_words_snackname,
		"%hot" = GLOB.vore_words_hot,
		"%snake" = GLOB.vore_words_snake,
	)
	data["min_belly_name"] = BELLIES_NAME_MIN
	data["max_belly_name"] = BELLIES_NAME_MAX
	preset_colors = user.read_preference(/datum/preference/text/preset_colors)

	return data

/datum/vore_look/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["unsaved_changes"] = unsaved_changes
	data["active_tab"] = active_tab
	data["presets"] = preset_colors
	var/list/merged_1 = ui_data_datum_vore_look(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /datum/vore_look's window data.
/datum/vore_look/proc/ui_data_datum_vore_look(mob/user, datum/tgui/_ui, datum/tgui_state/_state)
	var/list/data = list()

	if(!host())
		return data

	// General Data
	data["persist_edit_mode"] = host().persistend_edit_mode

	// Inisde Data
	data["inside"] = get_inside_data(host())

	data["host_mobtype"] = null
	data["show_pictures"] = null
	data["icon_overflow"] = null
	data["prey_abilities"] = null
	data["intent_data"] = null
	data["our_bellies"] = null
	data["selected"] = null
	data["soulcatcher"] = null
	data["abilities"] = null
	data["prefs"] = null
	data["general_pref_data"] = null

	switch(active_tab)
		if(VORE_BELLY_TAB)
			data["active_vore_tab"] = active_vore_tab
			data["host_mobtype"] = get_host_mobtype(host())

			// Content Data
			data["show_pictures"] = show_pictures
			data["icon_overflow"] = icon_overflow

			// List of all our bellies
			data["our_bellies"] = get_vorebellies(host())

			// Selected belly data. TODO, split this into sub data per tab, we don't need all of this at once, ever!
			data["selected"] = get_selected_data(host())

		if(VORE_INSIDE_TAB)
			// Content Data
			data["show_pictures"] = show_pictures
			data["icon_overflow"] = icon_overflow
			var/atom/hostloc = host().loc
			// Allow VorePanel to show pred belly details even while indirectly inside
			if(isliving(host()))
				var/mob/living/human_host = host()
				hostloc = human_host.surrounding_belly()
			data["prey_abilities"] = get_prey_abilities(host(), hostloc)
			data["intent_data"] = get_intent_data(host(), hostloc)

		if(SOULCATCHER_TAB)
			// Soulcatcher and abilities
			data["our_bellies"] = get_vorebellies(host(), FALSE)
			data["soulcatcher"] = get_soulcatcher_data(host())
			data["abilities"] = get_ability_data(host())

		if(PREFERENCE_TAB)
			// Preference data, we only ever need that when we go to the pref page!
			data["prefs"] = get_preference_data(host())
			// Content Data
			data["show_pictures"] = show_pictures
			data["icon_overflow"] = icon_overflow

		if(GENERAL_TAB)
			data["general_pref_data"] = get_general_data(host())
			data["our_bellies"] = get_vorebellies(host(), FALSE)

	return data

// A belly's settings: each attribute is a sub-action (panel_databackend/vorepanel_set_*attribute.dm) whose "val" has that attribute's own
// schema; the window sends "set_attribute"/"liq_set_attribute" with the attribute's name.
/datum/vore_look/proc/ui_act_set_attribute(datum/act/op/A, attribute, val, msgtype)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	return vore_nested(user, "attr", attribute, list("val" = val, "msgtype" = msgtype), ui)

/datum/vore_look/proc/ui_act_liq_set_attribute(datum/act/op/A, attribute, val, msgtype)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	return vore_nested(user, "liq", attribute, list("val" = val, "msgtype" = msgtype), ui)

/// One belly setting: refused without a selected belly; the belly reschedules after (turbo mode, liquid generation and other scheduled
/// settings may have changed). `ui` is the window the sub-action may ask in.
/datum/vore_look/proc/vore_nested(mob/user, namespace, attribute, list/data, datum/tgui/ui)
	if(!host().vore_selected)
		tgui_alert_async(user, "No belly selected to modify.")
		return FALSE
	. = namespace == "attr" ? attr_subaction(attribute, data, user, ui) : liq_subaction(attribute, data, user, ui)
	host().vore_selected?.belly_reschedule()

/datum/vore_look/proc/ui_act_change_tab(datum/act/op/A, tab)
	var/new_tab = tab
	if(isnum(new_tab))
		active_tab = new_tab
	return TRUE

/datum/vore_look/proc/ui_act_change_vore_tab(datum/act/op/A, tab)
	var/new_tab = tab
	if(isnum(new_tab))
		active_vore_tab = new_tab
	return TRUE

/datum/vore_look/proc/ui_act_change_message_option(datum/act/op/A, tab)
	var/new_tab = tab
	if(isnum(new_tab))
		message_option = new_tab
		message_subtab = null
		selected_message = null
	return TRUE

/datum/vore_look/proc/ui_act_change_message_type(datum/act/op/A, tab)
	var/new_tab = tab
	if(istext(new_tab))
		message_subtab = new_tab
		selected_message = null
	return TRUE

/datum/vore_look/proc/ui_act_set_current_message(datum/act/op/A, tab)
	var/new_tab = tab
	if(istext(new_tab))
		selected_message = new_tab
	return TRUE

/datum/vore_look/proc/ui_act_change_sc_message_option(datum/act/op/A, tab)
	var/new_tab = tab
	if(istext(new_tab))
		sc_message_subtab = new_tab
	return TRUE

/datum/vore_look/proc/ui_act_change_aset_message_option(datum/act/op/A, tab)
	var/new_tab = tab
	if(istext(new_tab))
		aset_message_subtab = new_tab
	return TRUE

/datum/vore_look/proc/ui_act_show_pictures(datum/act/op/A)
	show_pictures = !show_pictures
	return TRUE

/datum/vore_look/proc/ui_act_toggle_editmode_persistence(datum/act/op/A)
	host().persistend_edit_mode = !host().persistend_edit_mode
	return TRUE

/datum/vore_look/proc/ui_act_newbelly(datum/act/op/A, val)
	var/mob/user = A.actor
	if(length(host().vore_organs) >= BELLIES_MAX)
		return FALSE

	var/new_name = sanitize(val, BELLIES_NAME_MAX, FALSE, TRUE, FALSE)

	if(!new_name)
		return FALSE

	var/failure_msg
	if(length(new_name) > BELLIES_NAME_MAX || length(new_name) < BELLIES_NAME_MIN)
		failure_msg = "Entered belly name length invalid (must be longer than [BELLIES_NAME_MIN], no more than than [BELLIES_NAME_MAX])."
	else
		for(var/obj/belly/B as anything in host().vore_organs)
			if(lowertext(new_name) == lowertext(B.name))
				failure_msg = "No duplicate belly names, please."
				break

	if(failure_msg) //Something went wrong.
		tgui_alert_async(user, failure_msg, "Error!")
		return TRUE

	var/obj/belly/NB = new(host())
	NB.name = new_name
	host().vore_selected = NB
	//Ensures that new stomachs that are made have the same silicon overlay pref as the first stomach.
	if(LAZYLEN(host().vore_organs))
		var/obj/belly/belly_to_check = host().vore_organs[1]
		NB.silicon_belly_overlay_preference = belly_to_check.silicon_belly_overlay_preference
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_importpanel(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/vore_look/import_panel/importPanel
	if(!importPanel)
		importPanel = new(user)

	if(!importPanel)
		to_chat(user,span_notice("Import panel undefined: [importPanel]"))
		return FALSE

	importPanel.open_import_panel(user)
	return TRUE

/datum/vore_look/proc/ui_act_bellypick(datum/act/op/A, bellypick)
	if(isnull(bellypick))
		return FALSE
	host().vore_selected = bellypick
	return TRUE

/datum/vore_look/proc/ui_act_move_belly(datum/act/op/A, dir_arg)
	var/mob/user = A.actor
	var/dir = dir_arg
	if(LAZYLEN(host().vore_organs) <= 1)
		to_chat(user, span_warning("You can't sort bellies with only one belly to sort..."))
		return TRUE

	var/current_index = host().vore_organs.Find(host().vore_selected)
	if(current_index)
		var/new_index = clamp(current_index + dir, 1, LAZYLEN(host().vore_organs))
		host().vore_organs.Swap(current_index, new_index)
		unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_saveprefs(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	return vore_save_preferences_step(ui, list())

/datum/vore_look/proc/ui_act_reloadprefs(datum/act/op/A)
	if(A.step_value("reload") != "Reload")
		return FALSE
	return vore_reload_preferences_apply(A.actor)

/datum/vore_look/proc/ui_act_loadprefsfromslot(datum/act/op/A)
	if(A.step_value("load") != "Load")
		return FALSE
	return vore_load_preferences_apply()
//"Belly HTML Export Earlyport"

/datum/vore_look/proc/ui_act_exportpanel(datum/act/op/A)
	var/mob/user = A.actor
	if(!user)
		return FALSE

	var/datum/vore_look/export_panel/exportPanel
	if(!exportPanel)
		exportPanel = new(user)

	if(!exportPanel)
		to_chat(user,span_notice("Export panel undefined: [exportPanel]"))
		return FALSE

	exportPanel.open_export_panel(user)

	return TRUE

/datum/vore_look/proc/ui_act_taste_flavor(datum/act/op/A, val)
	host().vore_taste = sanitize(val, FLAVOR_MAX, FALSE, TRUE, FALSE)
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_smell_flavor(datum/act/op/A, val)
	host().vore_smell = sanitize(val, FLAVOR_MAX, FALSE, TRUE, FALSE)
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_dropnom_pred(datum/act/op/A)
	host().can_be_drop_pred = !host().can_be_drop_pred
	if(host().client.prefs_vr)
		host().client.prefs_vr.can_be_drop_pred = host().can_be_drop_pred
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_dropnom_prey(datum/act/op/A)
	host().can_be_drop_prey = !host().can_be_drop_prey
	if(host().client.prefs_vr)
		host().client.prefs_vr.can_be_drop_prey = host().can_be_drop_prey
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_afk_pred(datum/act/op/A)
	host().can_be_afk_pred = !host().can_be_afk_pred
	if(host().client.prefs_vr)
		host().client.prefs_vr.can_be_afk_pred = host().can_be_afk_pred
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_afk_prey(datum/act/op/A)
	host().can_be_afk_prey = !host().can_be_afk_prey
	if(host().client.prefs_vr)
		host().client.prefs_vr.can_be_afk_prey = host().can_be_afk_prey
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_latejoin_vore(datum/act/op/A)
	host().latejoin_vore = !host().latejoin_vore
	if(host().client.prefs_vr)
		host().client.prefs_vr.latejoin_vore = host().latejoin_vore
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_latejoin_prey(datum/act/op/A)
	host().latejoin_prey = !host().latejoin_prey
	if(host().client.prefs_vr)
		host().client.prefs_vr.latejoin_prey = host().latejoin_prey
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_allow_spontaneous_tf(datum/act/op/A)
	host().allow_spontaneous_tf = !host().allow_spontaneous_tf
	if(host().client.prefs_vr)
		host().client.prefs_vr.allow_spontaneous_tf = host().allow_spontaneous_tf
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_digest(datum/act/op/A)
	host().digestable = !host().digestable
	if(host().client.prefs_vr)
		host().client.prefs_vr.digestable = host().digestable
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_allowtemp(datum/act/op/A)
	host().allowtemp = !host().allowtemp
	if(host().client.prefs_vr)
		host().client.prefs_vr.allowtemp = host().allowtemp
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_global_privacy(datum/act/op/A)
	host().eating_privacy_global = !host().eating_privacy_global
	if(host().client.prefs_vr)
		host().client.prefs_vr.eating_privacy_global = host().eating_privacy_global
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_death_privacy(datum/act/op/A)
	host().vore_death_privacy = !host().vore_death_privacy
	if(host().client.prefs_vr)
		host().client.prefs_vr.vore_death_privacy = host().vore_death_privacy
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_mimicry(datum/act/op/A)
	host().allow_mimicry = !host().allow_mimicry
	if(host().client.prefs_vr)
		host().client.prefs_vr.allow_mimicry = host().allow_mimicry
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_devour(datum/act/op/A)
	host().devourable = !host().devourable
	if(host().client.prefs_vr)
		host().client.prefs_vr.devourable = host().devourable
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_resize(datum/act/op/A)
	host().resizable = !host().resizable
	if(host().client.prefs_vr)
		host().client.prefs_vr.resizable = host().resizable
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_feed(datum/act/op/A)
	host().feeding = !host().feeding
	if(host().client.prefs_vr)
		host().client.prefs_vr.feeding = host().feeding
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_absorbable(datum/act/op/A)
	host().absorbable = !host().absorbable
	if(host().client.prefs_vr)
		host().client.prefs_vr.absorbable = host().absorbable
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_leaveremains(datum/act/op/A)
	host().digest_leave_remains = !host().digest_leave_remains
	if(host().client.prefs_vr)
		host().client.prefs_vr.digest_leave_remains = host().digest_leave_remains
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_mobvore(datum/act/op/A)
	host().allowmobvore = !host().allowmobvore
	if(host().client.prefs_vr)
		host().client.prefs_vr.allowmobvore = host().allowmobvore
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_steppref(datum/act/op/A)
	host().step_mechanics_pref = !host().step_mechanics_pref
	if(host().client.prefs_vr)
		host().client.prefs_vr.step_mechanics_pref = host().step_mechanics_pref
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_pickuppref(datum/act/op/A)
	host().pickup_pref = !host().pickup_pref
	if(host().client.prefs_vr)
		host().client.prefs_vr.pickup_pref = host().pickup_pref
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_strippref(datum/act/op/A)
	host().strip_pref = !host().strip_pref
	if(host().client.prefs_vr)
		host().client.prefs_vr.strip_pref = host().strip_pref
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_contaminate_pref(datum/act/op/A)
	host().contaminate_pref = !host().contaminate_pref
	if(host().client.prefs_vr)
		host().client.prefs_vr.contaminate_pref = host().contaminate_pref
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_allow_mind_transfer(datum/act/op/A)
	host().allow_mind_transfer = !host().allow_mind_transfer
	if(host().client.prefs_vr)
		host().client.prefs_vr.allow_mind_transfer = host().allow_mind_transfer
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_healbelly(datum/act/op/A)
	host().permit_healbelly = !host().permit_healbelly
	if(host().client.prefs_vr)
		host().client.prefs_vr.permit_healbelly = host().permit_healbelly
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_fx(datum/act/op/A)
	host().show_vore_fx = !host().show_vore_fx
	if(host().client.prefs_vr)
		host().client.prefs_vr.show_vore_fx = host().show_vore_fx
	if (isbelly(host().loc))
		var/obj/belly/B = host().loc
		B.vore_fx(host())
	else
		host().clear_fullscreen("belly")
		host().belly_overlay_tgui?.hide() // hide TGUI belly overlay
	if(!host().hud_used.hud_shown)
		host().toggle_hud_vis()
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_noisy(datum/act/op/A)
	host().noisy = !host().noisy
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_set_max_voreoverlay_alpha(datum/act/op/A, val)
	var/new_alpha = CLAMP(val, 0, 255)
	host().max_voreoverlay_alpha = new_alpha
	if(host().client.prefs_vr)
		host().client.prefs_vr.max_voreoverlay_alpha = host().max_voreoverlay_alpha
	if (isbelly(host().loc))
		var/obj/belly/B = host().loc
		B.vore_fx(host())
	unsaved_changes = TRUE
	return TRUE
// liquid belly code

/datum/vore_look/proc/ui_act_toggle_liq_rec(datum/act/op/A)
	host().receive_reagents = !host().receive_reagents
	if(host().client.prefs_vr)
		host().client.prefs_vr.receive_reagents = host().receive_reagents
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_liq_giv(datum/act/op/A)
	host().give_reagents = !host().give_reagents
	if(host().client.prefs_vr)
		host().client.prefs_vr.give_reagents = host().give_reagents
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_liq_apply(datum/act/op/A)
	host().apply_reagents = !host().apply_reagents
	if(host().client.prefs_vr)
		host().client.prefs_vr.apply_reagents = host().apply_reagents
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_autotransferable(datum/act/op/A)
	host().autotransferable = !host().autotransferable
	if(host().client.prefs_vr)
		host().client.prefs_vr.autotransferable = host().autotransferable
	unsaved_changes = TRUE
	return TRUE
//Belch code

/datum/vore_look/proc/ui_act_toggle_noisy_full(datum/act/op/A)
	host().noisy_full = !host().noisy_full
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_drop_vore(datum/act/op/A)
	host().drop_vore = !host().drop_vore
	if(host().client.prefs_vr)
		host().client.prefs_vr.drop_vore = host().drop_vore
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_slip_vore(datum/act/op/A)
	host().slip_vore = !host().slip_vore
	if(host().client.prefs_vr)
		host().client.prefs_vr.slip_vore = host().slip_vore
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_stumble_vore(datum/act/op/A)
	host().stumble_vore = !host().stumble_vore
	if(host().client.prefs_vr)
		host().client.prefs_vr.stumble_vore = host().stumble_vore
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_throw_vore(datum/act/op/A)
	host().throw_vore = !host().throw_vore
	if(host().client.prefs_vr)
		host().client.prefs_vr.throw_vore = host().throw_vore
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_phase_vore(datum/act/op/A)
	host().phase_vore = !host().phase_vore
	if(host().client.prefs_vr)
		host().client.prefs_vr.phase_vore = host().phase_vore
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_food_vore(datum/act/op/A)
	host().food_vore = !host().food_vore
	if(host().client.prefs_vr)
		host().client.prefs_vr.food_vore = host().food_vore
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_consume_liquid_belly(datum/act/op/A)
	host().consume_liquid_belly = !host().consume_liquid_belly
	if(host().client.prefs_vr)
		host().client.prefs_vr.consume_liquid_belly = host().consume_liquid_belly
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_digest_pain(datum/act/op/A)
	host().digest_pain = !host().digest_pain
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_switch_selective_mode_pref(datum/act/op/A, val)
	var/new_selective_preference = val
	if(new_selective_preference == host().selective_preference)
		return FALSE
	host().selective_preference = new_selective_preference
	if(host().client.prefs_vr)
		host().client.prefs_vr.selective_preference = host().selective_preference
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_switch_strip_mode_pref(datum/act/op/A, val)
	var/new_size_strip_pref = val
	new_size_strip_pref = clamp(new_size_strip_pref, SIZESTRIP_NONE, SIZESTRIP_ALL)
	if(new_size_strip_pref == host().size_strip_preference)
		return FALSE
	host().size_strip_preference = new_size_strip_pref
	if(host().client.prefs_vr)
		host().client.prefs_vr.size_strip_preference = host().size_strip_preference
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_nutrition_ex(datum/act/op/A)
	host().nutrition_message_visible = !host().nutrition_message_visible
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_weight_ex(datum/act/op/A)
	host().weight_message_visible = !host().weight_message_visible
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_set_vs_color(datum/act/op/A, attribute, val)
	var/belly_choice = attribute
	if(!(belly_choice in host().vore_icon_bellies))
		return FALSE
	var/newcolor = sanitize_hexcolor(lowertext(val))
	if(!newcolor)
		return FALSE
	host().vore_sprite_color[belly_choice] = newcolor
	host().update_icons_body()
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_vs_multiply(datum/act/op/A, attribute)
	var/belly_choice = attribute
	if(!(belly_choice in host().vore_icon_bellies))
		return FALSE
	if(!host().vore_sprite_multiply[belly_choice])
		host().vore_sprite_multiply[belly_choice] = TRUE
	else
		host().vore_sprite_multiply[belly_choice] = !host().vore_sprite_multiply[belly_choice]
	host().update_icons_body()
	unsaved_changes = TRUE
	return TRUE
//vore sprites color

/datum/vore_look/proc/ui_act_set_belly_rub(datum/act/op/A, val)
	var/rub_target = html_encode(val)
	if(rub_target == "Current Selected")
		host().belly_rub_target = null
	else
		host().belly_rub_target = rub_target
	if(host().client.prefs_vr)
		host().client.prefs_vr.belly_rub_target = host().belly_rub_target
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_no_latejoin_vore_warning(datum/act/op/A)
	host().no_latejoin_vore_warning = !host().no_latejoin_vore_warning
	if(host().client.prefs_vr)
		host().client.prefs_vr.no_latejoin_vore_warning = host().no_latejoin_vore_warning
	if(host().no_latejoin_vore_warning_persists)
		unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_no_latejoin_prey_warning(datum/act/op/A)
	host().no_latejoin_prey_warning = !host().no_latejoin_prey_warning
	if(host().client.prefs_vr)
		host().client.prefs_vr.no_latejoin_prey_warning = host().no_latejoin_prey_warning
	if(host().no_latejoin_prey_warning_persists)
		unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_adjust_no_latejoin_vore_warning_time(datum/act/op/A, new_pred_time)
	host().no_latejoin_vore_warning_time = new_pred_time
	if(host().client.prefs_vr)
		host().client.prefs_vr.no_latejoin_vore_warning_time = host().no_latejoin_vore_warning_time
	if(host().no_latejoin_vore_warning_persists)
		unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_adjust_no_latejoin_prey_warning_time(datum/act/op/A, new_prey_time)
	host().no_latejoin_prey_warning_time = new_prey_time
	if(host().client.prefs_vr)
		host().client.prefs_vr.no_latejoin_prey_warning_time = host().no_latejoin_prey_warning_time
	if(host().no_latejoin_prey_warning_persists)
		unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_no_latejoin_vore_warning_persists(datum/act/op/A)
	host().no_latejoin_vore_warning_persists = !host().no_latejoin_vore_warning_persists
	if(host().client.prefs_vr)
		host().client.prefs_vr.no_latejoin_vore_warning_persists = host().no_latejoin_vore_warning_persists
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_no_latejoin_prey_warning_persists(datum/act/op/A)
	host().no_latejoin_prey_warning_persists = !host().no_latejoin_prey_warning_persists
	if(host().client.prefs_vr)
		host().client.prefs_vr.no_latejoin_prey_warning_persists = host().no_latejoin_prey_warning_persists
	unsaved_changes = TRUE
	return TRUE
//Soulcatcher prefs

/datum/vore_look/proc/ui_act_toggle_soulcatcher_allow_capture(datum/act/op/A)
	host().soulcatcher_pref_flags ^= SOULCATCHER_ALLOW_CAPTURE
	if(host().client.prefs_vr)
		host().client.prefs_vr.soulcatcher_pref_flags = host().soulcatcher_pref_flags
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_soulcatcher_allow_transfer(datum/act/op/A)
	host().soulcatcher_pref_flags ^= SOULCATCHER_ALLOW_TRANSFER
	if(host().client.prefs_vr)
		host().client.prefs_vr.soulcatcher_pref_flags = host().soulcatcher_pref_flags
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_soulcatcher_allow_takeover(datum/act/op/A)
	host().soulcatcher_pref_flags ^= SOULCATCHER_ALLOW_TAKEOVER
	if(host().client.prefs_vr)
		host().client.prefs_vr.soulcatcher_pref_flags = host().soulcatcher_pref_flags
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_soulcatcher_allow_deletion(datum/act/op/A)
	var/current_number = global_flag_check(host().soulcatcher_pref_flags, SOULCATCHER_ALLOW_DELETION) + global_flag_check(host().soulcatcher_pref_flags, SOULCATCHER_ALLOW_DELETION_INSTANT)
	switch(current_number)
		if(0)
			host().soulcatcher_pref_flags ^= SOULCATCHER_ALLOW_DELETION
		if(1)
			host().soulcatcher_pref_flags ^= SOULCATCHER_ALLOW_DELETION_INSTANT
		if(2)
			host().soulcatcher_pref_flags &= ~(SOULCATCHER_ALLOW_DELETION)
			host().soulcatcher_pref_flags &= ~(SOULCATCHER_ALLOW_DELETION_INSTANT)
	if(host().client.prefs_vr)
		host().client.prefs_vr.soulcatcher_pref_flags = host().soulcatcher_pref_flags
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_adjust_own_size(datum/act/op/A, new_mob_size)
	var/new_size = new_mob_size
	new_size = clamp(new_size, RESIZE_MINIMUM_DORMS, RESIZE_MAXIMUM_DORMS)
	if(istype(host(), /mob/living))
		var/mob/living/living_host = host()
		if(new_size == living_host.size_multiplier)
			return FALSE
		if(living_host.nutrition >= VORE_RESIZE_COST)
			living_host.adjust_nutrition(-VORE_RESIZE_COST)
			living_host.resize(new_size, uncapped = living_host.has_large_resize_bounds(), ignore_prefs = TRUE)
	return TRUE
//Soulcatcher functions

/datum/vore_look/proc/ui_act_soulcatcher_release_all(datum/act/op/A)
	host().soulgem.release_mobs()
	return TRUE

/datum/vore_look/proc/ui_act_soulcatcher_erase_all(datum/act/op/A)
	host().soulgem.erase_mobs()
	return TRUE

/datum/vore_look/proc/ui_act_soulcatcher_release(datum/act/op/A)
	host().soulgem.release_selected()
	return TRUE

/datum/vore_look/proc/ui_act_soulcatcher_transfer(datum/act/op/A)
	host().soulgem.transfer_selected()
	return TRUE

/datum/vore_look/proc/ui_act_soulcatcher_delete(datum/act/op/A)
	host().soulgem.delete_selected()
	return TRUE

/datum/vore_look/proc/ui_act_soulcatcher_transfer_control(datum/act/op/A)
	host().soulgem.take_control_selected()
	return TRUE

/datum/vore_look/proc/ui_act_soulcatcher_release_control(datum/act/op/A)
	host().soulgem.take_control_owner()
	return TRUE

/datum/vore_look/proc/ui_act_soulcatcher_select(datum/act/op/A, selected_soul_arg)
	if(isnull(selected_soul_arg))
		return FALSE
	var/mob/picked_soul = selected_soul_arg
	if(picked_soul && (picked_soul in host().soulgem.brainmobs))
		rel_set(host().soulgem, nameof(/obj/soulgem::selected_soul), picked_soul)
	return TRUE
//Soulcatcher settings

/datum/vore_look/proc/ui_act_soulcatcher_toggle(datum/act/op/A)
	host().soulgem.toggle_setting(SOULGEM_ACTIVE)
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_soulcatcher_sfx(datum/act/op/A, val)
	var/obj/belly = val
	if(!istype(belly))
		host().soulgem.update_linked_belly(null)
		return TRUE
	host().soulgem.update_linked_belly(belly)
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_self_catching(datum/act/op/A)
	host().soulgem.toggle_setting(NIF_SC_CATCHING_ME)
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_prey_catching(datum/act/op/A)
	host().soulgem.toggle_setting(NIF_SC_CATCHING_OTHERS)
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_drain_catching(datum/act/op/A)
	host().soulgem.toggle_setting(SOULGEM_CATCHING_DRAIN)
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_ghost_catching(datum/act/op/A)
	host().soulgem.toggle_setting(SOULGEM_CATCHING_GHOSTS)
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_ext_hearing(datum/act/op/A)
	host().soulgem.toggle_setting(NIF_SC_ALLOW_EARS)
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_ext_vision(datum/act/op/A)
	host().soulgem.toggle_setting(NIF_SC_ALLOW_EYES)
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_mind_backup(datum/act/op/A)
	host().soulgem.toggle_setting(NIF_SC_BACKUPS)
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_sr_projecting(datum/act/op/A)
	host().soulgem.toggle_setting(NIF_SC_PROJECTING)
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_vore_sfx(datum/act/op/A)
	host().soulgem.toggle_setting(SOULGEM_SHOW_VORE_SFX)
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_toggle_sr_vision(datum/act/op/A)
	host().soulgem.toggle_setting(SOULGEM_SEE_SR_SOULS)
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_soulcatcher_rename(datum/act/op/A, val)
	var/new_name = val
	if(!host().soulgem.rename(new_name))
		return FALSE
	unsaved_changes = TRUE
	return TRUE

/datum/vore_look/proc/ui_act_sc_interior_message(datum/act/op/A, val)
	var/new_flavor = val
	if(new_flavor)
		unsaved_changes = TRUE
		host().soulgem.adjust_interior(new_flavor)
	return TRUE

/datum/vore_look/proc/ui_act_sc_capture_meesage(datum/act/op/A, val)
	var/message = val
	if(message)
		unsaved_changes = TRUE
		host().soulgem.set_custom_message(message, SC_CAPTURE_MEESAGE)
	return TRUE

/datum/vore_look/proc/ui_act_sc_transit_message(datum/act/op/A, val)
	var/message = val
	if(message)
		unsaved_changes = TRUE
		host().soulgem.set_custom_message(message, SC_TRANSIT_MESSAGE)
	return TRUE

/datum/vore_look/proc/ui_act_sc_release_message(datum/act/op/A, val)
	var/message = val
	if(message)
		unsaved_changes = TRUE
		host().soulgem.set_custom_message(message, SC_RELEASE_MESSAGE)
	return TRUE

/datum/vore_look/proc/ui_act_sc_transfere_message(datum/act/op/A, val)
	var/message = val
	if(message)
		unsaved_changes = TRUE
		host().soulgem.set_custom_message(message, SC_TRANSFERE_MESSAGE)
	return TRUE

/datum/vore_look/proc/ui_act_sc_delete_message(datum/act/op/A, val)
	var/message = val
	if(message)
		unsaved_changes = TRUE
		host().soulgem.set_custom_message(message, SC_DELETE_MESSAGE)
	return TRUE

/datum/vore_look/proc/ui_act_preset(datum/act/op/A, color, index_arg)
	var/raw_data = lowertext(color)
	var/index = index_arg
	var/list/entries = splittext(preset_colors, ";")
	while(LAZYLEN(entries) < 20)
		entries += "#FFFFFF"
	if(LAZYLEN(entries) > 20)
		entries.Cut(21)
	var/hex = sanitize_hexcolor(raw_data)
	if (!hex || !isnum(index) || entries[index] == hex)
		return
	entries[index] = hex
	preset_colors = entries.Join(";")
	return TRUE

/datum/vore_look/proc/ui_act_pick_from_inside(datum/act/op/A, pick, belly, option)
	var/mob/user = A.actor
	if(isnull(pick))
		return FALSE
	if(isnull(belly))
		return FALSE
	return pick_from_inside(user, list("pick" = pick, "belly" = belly, "option" = option))

/// Host is inside someone else, and is trying to interact with something else inside that person.
/datum/vore_look/proc/pick_from_inside(mob/user, list/params)
	var/atom/movable/target = params["pick"]
	var/obj/belly/OB = params["belly"]

	if(!(target in OB))
		return TRUE // Aren't here anymore, need to update menu

	var/intent = "Examine"
	// Only allow indirect belly viewers to examine
	if(user in OB)
		if(isliving(target))
			if(params["option"] in list("Examine","Help Out","Devour"))
				intent = params["option"]
			else
				var/_answer_a1 = rerun_ask(user, "a1", PROC_REF(pick_from_inside), args, /datum/prompt/choice, question = "What do you want to do to them?", title = "Query", choices = list("Examine","Help Out","Devour"), buttons = TRUE)
				if(isnull(_answer_a1))
					return
				intent = _answer_a1

		else if(isitem(target))
			if(params["option"] in list("Examine","Use Hand"))
				intent = params["option"]
			else
				var/_answer_a2 = rerun_ask(user, "a2", PROC_REF(pick_from_inside), args, /datum/prompt/choice, question = "What do you want to do to that?", title = "Query", choices = list("Examine","Use Hand"), buttons = TRUE)
				if(isnull(_answer_a2))
					return
				intent = _answer_a2
	//End of indirect vorefx changes

	switch(intent)
		if("Examine") //Examine a mob inside another mob
			var/list/results = target.examine(host())
			if(!results || !results.len)
				results = list("You were unable to examine that. Tell a developer!")
			to_chat(user, jointext(results, "<br>"))
			if(isliving(target))
				var/mob/living/ourtarget = target
				ourtarget.chat_healthbar(user, TRUE)
			return TRUE

		if("Use Hand")
			if(host().stat)
				to_chat(user, span_warning("You can't do that in your state!"))
				return TRUE

			host().ClickOn(target)
			return TRUE

	if(!isliving(target))
		return FALSE

	var/mob/living/M = target
	switch(intent)
		if("Help Out") //Help the inside-mob out
			if(host().stat || host().absorbed || M.absorbed)
				to_chat(user, span_warning("You can't do that in your state!"))
				return TRUE

			to_chat(user,span_vnotice("[span_green("You begin to push [M] to freedom!")]"))
			to_chat(M,span_vnotice("[host()] begins to push you to freedom!"))
			to_chat(OB.owner,span_vwarning("Someone is trying to escape from inside you!"))
			after(OB, 5 SECONDS, TYPE_PROC_REF(/obj/belly, help_out_done), with = list(user, M, host()))
			return TRUE

		if("Devour") //Eat the inside mob
			if(host().absorbed || host().stat)
				to_chat(user,span_warning("You can't do that in your state!"))
				return TRUE

			if(!host().vore_selected)
				to_chat(user,span_warning("Pick a belly on yourself first!"))
				return TRUE

			var/obj/belly/TB = host().vore_selected
			to_chat(user,span_vwarning("You begin to [lowertext(TB.vore_verb)] [M] into your [lowertext(TB.name)]!"))
			to_chat(M,span_vwarning("[host()] begins to [lowertext(TB.vore_verb)] you into their [lowertext(TB.name)]!"))
			to_chat(OB.owner,span_vwarning("Someone inside you is eating someone else!"))

			//Not a timed action: in a stomach, weird things abound.
			after(OB, TB.nonhuman_prey_swallow_time, TYPE_PROC_REF(/obj/belly, inner_devour_done), with = list(user, M, host(), TB))

/// A mob inside this belly helped `M` out (vore panel), after the wait.
/obj/belly/proc/help_out_done(mob/user, mob/living/M, mob/living/host)
	if(!(M?.loc == src))
		return
	if(prob(33))
		release_specific_contents(M)
		to_chat(user,span_vnotice("[span_green("You manage to help [M] to safety!")]"))
		to_chat(M, span_vnotice("[span_green("[host] pushes you free!")]"))
		to_chat(owner,span_valert("[M] forces free of the confines of your body!"))
	else
		to_chat(user,span_valert("[M] slips back down inside despite your efforts."))
		to_chat(M,span_valert("Even with [host]'s help, you slip back inside again."))
		to_chat(owner,span_vnotice("[span_green("Your body efficiently shoves [M] back where they belong.")]"))

/// A mob inside this belly ate `M` into its own belly `TB` (vore panel), after the wait.
/obj/belly/proc/inner_devour_done(mob/user, mob/living/M, mob/living/host, obj/belly/TB)
	if(TB && (host?.loc == src) && (M?.loc == src)) //Make sure they're still here.
		to_chat(user,span_vwarning("You manage to [lowertext(TB.vore_verb)] [M] into your [lowertext(TB.name)]!"))
		to_chat(M,span_vwarning("[host] manages to [lowertext(TB.vore_verb)] you into their [lowertext(TB.name)]!"))
		to_chat(owner,span_vwarning("Someone inside you has eaten someone else!"))
		if(M.absorbed)
			M.set_absorbed(FALSE)
			handle_absorb_langs(M, owner)
		TB.nom_atom(M)

/datum/vore_look/proc/ui_act_pick_from_outside(datum/act/op/A, pickall, intent, val, pick, option, targetBelly)
	var/mob/user = A.actor
	if(isnull(val))
		return FALSE
	if(isnull(pick))
		return FALSE
	if(isnull(targetBelly))
		return FALSE
	return pick_from_outside(user, list("pickall" = pickall, "intent" = intent, "val" = val, "pick" = pick, "option" = option, "targetBelly" = targetBelly))

/// Host is trying to interact with something in host's belly (its answers re-run it with rerun_ask()).
/datum/vore_look/proc/pick_from_outside(mob/user, list/params)
	var/intent

	if(params["pickall"])
		return pick_all_from_outside(user, params)

	var/atom/movable/target = params["pick"]
	if(!(target in host().vore_selected))
		return TRUE // Not in our X anymore, update UI
	var/list/available_options = list("Examine", "Eject", "Launch", "Move", "Transfer")
	if(ishuman(target))
		available_options += "Transform"
		available_options += "Health Check"
	if(isobserver(target) || istype(target,/obj/item/mmi))
		available_options += "Reform"

	if(isliving(target))
		var/mob/living/datarget = target
		if(datarget.client)
			available_options += "Process"
		available_options += "Health"
	if((params["option"] in available_options))
		intent = params["option"]
	else
		var/_answer_a1 = rerun_ask(user, "a1", PROC_REF(pick_from_outside), args, /datum/prompt/choice, question = "What would you like to do with [target]?", title = "Vore Pick", choices = available_options)
		if(isnull(_answer_a1))
			return
		intent = _answer_a1
	switch(intent)
		if("Examine")
			return pick_examine(user, target, params)
		if("Eject")
			return pick_eject(user, target, params)
		if("Launch")
			return pick_launch(user, target, params)
		if("Move")
			return pick_move(user, target, params)
		if("Transfer")
			return pick_transfer(user, target, params)
		if("Transform")
			return pick_transform(user, target, params)
		if("Reform")
			return pick_reform(user, target, params)
		if("Health")
			return pick_health(user, target, params)
		if("Process")
			return pick_process(user, target, params)
		if("Health Check")
			return pick_health_check(user, target, params)

/// The [All] choices: eject or move everything in the selected belly.
/datum/vore_look/proc/pick_all_from_outside(mob/user, params)
	switch(params["intent"])
		if("eject_all")
			if(host().stat)
				to_chat(user,span_warning("You can't do that in your state!"))
				return TRUE

			host().vore_selected.release_all_contents()
			return TRUE

		if("move_all")
			if(host().stat)
				to_chat(user,span_warning("You can't do that in your state!"))
				return TRUE

			var/obj/belly/choice = params["val"]
			if(!choice)
				return FALSE

			for(var/atom/movable/target in host().vore_selected)
				to_chat(target,span_vwarning("You're squished from [host()]'s [lowertext(host().vore_selected)] to their [lowertext(choice.name)]!"))
				// Send the transfer message to indirect targets as well. Slightly different message because why not.
				to_chat(host().vore_selected.get_belly_surrounding(target.contents),span_warning("You're squished along with [target] from [host()]'s [lowertext(host().vore_selected)] to their [lowertext(choice.name)]!"))
				host().vore_selected.transfer_contents(target, choice, TRUE)
			host().vore_selected.handle_visual_update()
			return TRUE
	return FALSE

/// "Examine": Examine the prey and show its health bar.
/datum/vore_look/proc/pick_examine(mob/user, atom/movable/target, params)
	var/list/results = target.examine(host())
	if(!results || !results.len)
		results = list("You were unable to examine that. Tell a developer!")
	to_chat(user, jointext(results, "<br>"))
	if(isliving(target))
		var/mob/living/ourtarget = target
		ourtarget.chat_healthbar(user, TRUE)
	return TRUE

/// "Eject": Release the prey.
/datum/vore_look/proc/pick_eject(mob/user, atom/movable/target, params)
	if(host().stat)
		to_chat(user,span_warning("You can't do that in your state!"))
		return TRUE

	host().vore_selected.release_specific_contents(target)
	return TRUE

/// "Launch": Release the prey and throw it.
/datum/vore_look/proc/pick_launch(mob/user, atom/movable/target, params)
	if(host().stat)
		to_chat(user, span_warning("You can't do that in your state!"))
		return TRUE

	host().vore_selected.release_specific_contents(target)
	target.throw_at(get_edge_target_turf(host(), host().dir), 3, 1, host())
	host().visible_message(span_danger("[host()] launches [target]!"))
	return TRUE

/// "Move": Move the prey to another of our bellies. Prompts re-run pick_from_outside.
/datum/vore_look/proc/pick_move(mob/user, atom/movable/target, params)
	if(host().stat)
		to_chat(user,span_warning("You can't do that in your state!"))
		return TRUE
	var/obj/belly/choice = params["targetBelly"]
	if(!(choice in host().vore_organs))
		var/_answer_a2 = rerun_ask(user, "a2", PROC_REF(pick_from_outside), list(user, params), /datum/prompt/choice, question = "Move [target] where?", title = "Select Belly", choices = host().vore_organs)
		if(isnull(_answer_a2))
			return
		choice = _answer_a2
	if(!choice || !(target in host().vore_selected))
		return TRUE
	to_chat(target,span_vwarning("You're squished from [host()]'s [lowertext(host().vore_selected.name)] to their [lowertext(choice.name)]!"))
	// Send the transfer message to indirect targets as well. Slightly different message because why not.
	to_chat(host().vore_selected.get_belly_surrounding(target.contents),span_warning("You're squished along with [target] from [host()]'s [lowertext(host().vore_selected)] to their [lowertext(choice.name)]!"))
	host().vore_selected.transfer_contents(target, choice)

/// "Transfer": Offer the prey to an adjacent predator's belly. Prompts re-run pick_from_outside.
/datum/vore_look/proc/pick_transfer(mob/user, atom/movable/target, params)
	if(host().stat)
		to_chat(user,span_warning("You can't do that in your state!"))
		return TRUE

	var/mob/living/belly_owner = host()

	var/list/viable_candidates = list()
	for(var/mob/living/candidate in range(1, host()))
		if(istype(candidate) && !(candidate == host()))
			if(length(candidate.vore_organs) && candidate.feeding && !candidate.no_vore)
				viable_candidates += candidate
	if(!viable_candidates.len)
		to_chat(user, span_notice("There are no viable candidates around you!"))
		return TRUE
	var/_answer_a3 = rerun_ask(user, "a3", PROC_REF(pick_from_outside), list(user, params), /datum/prompt/choice, question = "Who do you want to receive the target?", title = "Select Predator", choices = viable_candidates)
	if(isnull(_answer_a3))
		return
	belly_owner = _answer_a3

	if(!belly_owner || !(belly_owner in range(1, host())))
		return TRUE

	var/obj/belly/choice = rerun_ask(user, "a4", PROC_REF(pick_from_outside), list(user, params), /datum/prompt/choice, question = "Move [target] where?", title = "Select Belly", choices = belly_owner.vore_organs)
	if(isnull(choice))
		return
	if(!choice || !(target in host().vore_selected) || !belly_owner || !(belly_owner in range(1, host())))
		return TRUE

	if(belly_owner != host())
		to_chat(user, span_vnotice("Transfer offer sent. Await their response."))
		var/accepted = rerun_ask(belly_owner, "a5", PROC_REF(pick_from_outside), list(user, params), /datum/prompt/choice, question = "[host()] is trying to transfer [target] from their [lowertext(host().vore_selected.name)] into your [lowertext(choice.name)]. Do you accept?", title = "Feeding Offer", choices = list("Yes", "No"), buttons = TRUE)
		if(isnull(accepted))
			return
		if(accepted != "Yes")
			to_chat(user, span_vwarning("[belly_owner] refused the transfer!!"))
			return TRUE
		if(!belly_owner || !(belly_owner in range(1, host())))
			return TRUE
		to_chat(target,span_vwarning("You're squished from [host()]'s [lowertext(host().vore_selected.name)] to [belly_owner]'s [lowertext(choice.name)]!"))
		to_chat(belly_owner,span_vwarning("[target] is squished from [host()]'s [lowertext(host().vore_selected.name)] to your [lowertext(choice.name)]!"))
		host().vore_selected.transfer_contents(target, choice)
	else
		to_chat(target,span_vwarning("You're squished from [host()]'s [lowertext(host().vore_selected.name)] to their [lowertext(choice.name)]!"))
		host().vore_selected.transfer_contents(target, choice)
	return TRUE

/// "Transform": Open the appearance changer on a human prey.
/datum/vore_look/proc/pick_transform(mob/user, atom/movable/target, params)
	if(host().stat)
		to_chat(user,span_warning("You can't do that in your state!"))
		return TRUE

	var/mob/living/carbon/human/H = target
	if(!istype(H))
		return FALSE

	if(!H.allow_spontaneous_tf)
		to_chat(user,span_warning("Your target can't be transformed!"))
		return FALSE

	var/datum/tgui_module/appearance_changer/vore/V = new(host(), H)
	V.tgui_interact(user)
	return TRUE

/// "Reform": Reform a ghost or MMI prey into its backed-up body. Prompts re-run pick_from_outside.
/datum/vore_look/proc/pick_reform(mob/user, atom/movable/target, params)
	if(host().stat)
		to_chat(user,span_warning("You can't do that in your state!"))
		return TRUE

	if(isobserver(target))
		reform_ghost_prey(user, target, params)
	else if(istype(target, /obj/item/mmi))
		reform_mmi_prey(user, target, params)
	return TRUE

/// Reform a ghost prey into its body backup, inside the selected belly.
/datum/vore_look/proc/reform_ghost_prey(mob/user, mob/observer/target, params)
	var/mob/observer/T = target
	if(!ismob(T.body_backup) || GLOB.prevent_respawns.Find(T.mind.name) || ispAI(T.body_backup))
		to_chat(user,span_warning("They don't seem to be reformable!"))
		return TRUE

	var/accepted = rerun_ask(T, "a6", PROC_REF(pick_from_outside), list(user, params), /datum/prompt/choice, question = "[host()] is trying to reform your body! Would you like to get reformed inside [host()]'s [lowertext(host().vore_selected.name)]?", title = "Reforming Attempt", choices = list("Yes", "No"), buttons = TRUE)
	if(isnull(accepted))
		return
	if(accepted != "Yes")
		to_chat(user,span_warning("[T] refused to be reformed!"))
		return TRUE
	if(!isbelly(T.loc))
		to_chat(user,span_warning("[T] is no longer inside to be reformed!"))
		to_chat(T,span_warning("You can't be reformed outside of a belly!"))
		return TRUE

	if(isliving(T.body_backup))
		var/mob/living/body_backup = T.body_backup
		if(ishuman(body_backup))
			var/mob/living/carbon/human/H = body_backup
			H.reform_restore("reformed in [host()]", host())
		else
			body_backup.revive()
		body_backup.forceMove(T.loc)
		release(body_backup, STAT_SUSPENDED, body_backup)
		body_backup.ajourn = 0
		transfer_mind(T.mind, body_backup, "reformed in [host()]", force = TRUE)
		rel_clear(body_backup, nameof(body_backup.teleop))
		rel_take(T, nameof(T.body_backup))
		host().vore_selected.release_specific_contents(T, TRUE)
		if(istype(body_backup, /mob/living/simple_mob))
			var/mob/living/simple_mob/sm = body_backup
			if(sm.icon_rest && sm.resting)
				sm.icon_state = sm.icon_rest
			else
				sm.icon_state = sm.icon_living
		announce_ghost_joinleave(T.mind, 0, "They now occupy their body again.")

/// Reform an MMI prey: its body backup is revived around it.
/datum/vore_look/proc/reform_mmi_prey(mob/user, obj/item/mmi/target, params)
	var/obj/item/mmi/MMI = target
	var/mob/living/carbon/brain/mmi_occupant = MMI.get_occupant()
	var/datum/mind_host/mmi_host = get_mind_host(MMI)
	if(!ismob(MMI.body_backup) || !mmi_occupant?.mind || GLOB.prevent_respawns.Find(mmi_occupant.mind.name))
		to_chat(user,span_warning("They don't seem to be reformable!"))
		return TRUE
	var/accepted = rerun_ask(mmi_occupant, "a7", PROC_REF(pick_from_outside), list(user, params), /datum/prompt/choice, question = "[host()] is trying to reform your body! Would you like to get reformed inside [host()]'s [lowertext(host().vore_selected.name)]?", title = "Reforming Attempt", choices = list("Yes", "No"), buttons = TRUE)
	if(isnull(accepted))
		return
	if(accepted != "Yes")
		to_chat(user,span_warning("[MMI] refused to be reformed!"))
		return TRUE

	if(isliving(MMI.body_backup))
		var/mob/living/body_backup = MMI.body_backup
		release(body_backup, STAT_SUSPENDED, body_backup)
		body_backup.forceMove(MMI.loc)
		body_backup.ajourn = 0
		rel_clear(body_backup, nameof(body_backup.teleop))
		//And now installing the MMI into the body...
		if(isrobot(body_backup)) //Just do the reverse of getting the MMI pulled out in /obj/belly/proc/digestion_death
			var/mob/living/silicon/robot/R = body_backup
			R.revive()
			mmi_host.release_mind(R, "reformed by [key_name(user)]")
			move_into(R, nameof(R.mmi), MMI)
			R.add_language(LANGUAGE_ROBOT_TALK)
		else // the same install as the surgery step (install_mmi_holder())
			install_mmi_holder(body_backup, MMI)

			mmi_host.release_mind(body_backup, "reformed by [key_name(user)]")
			//You've hopefully already named yourself, so... not implementing that bit.
			var/mob/living/carbon/human/H = body_backup
			H.reform_restore("reformed around [MMI] in [host()]", host())
		rel_take(MMI, nameof(MMI.body_backup))

/// "Health": Report the prey's vitality.
/datum/vore_look/proc/pick_health(mob/user, atom/movable/target, params)
	var/mob/living/ourtarget = target
	to_chat(user, span_notice("Current health reading for \The [ourtarget]: [round(ourtarget.vitality() * 100)]%"))
	return TRUE

/// "Process": Instantly digest, absorb, break or knock out a consenting prey. Prompts re-run pick_from_outside.
/datum/vore_look/proc/pick_process(mob/user, atom/movable/target, params)
	var/mob/living/ourtarget = target
	var/list/process_options = list()

	if(ourtarget.digestable)
		process_options += "Digest"
		process_options += "Break Bone"

	if(ourtarget.absorbable)
		process_options += "Absorb"

	process_options += "Knockout" //Can't think of any mechanical prefs that would restrict this. Even if they are already asleep, you may want to make it permanent.

	if(process_options.len)
		process_options += "Cancel"
	else
		to_chat(user, span_vwarning("You cannot instantly process [ourtarget]."))
		return FALSE

	var/ourchoice = rerun_ask(user, "a8", PROC_REF(pick_from_outside), list(user, params), /datum/prompt/choice, question = "How would you prefer to process \the [target]? This will perform the given action instantly if the prey accepts.", title = "Instant Process", choices = process_options)
	if(isnull(ourchoice))
		return
	if(!ourchoice)
		return FALSE
	if(!ourtarget.client)
		to_chat(user, span_vwarning("You cannot instantly process [ourtarget]."))
		return FALSE
	var/obj/belly/b = ourtarget.loc
	if(!istype(b) || b.owner != user)
		to_chat(user, span_vwarning("[ourtarget] isn't in your belly."))
		return FALSE
	switch(ourchoice)
		if("Digest")
			return b.instant_digest(user, ourtarget)
		if("Break Bone")
			return b.instant_break_bone(user, ourtarget)
		if("Absorb")
			return b.instant_absorb(user, ourtarget)
		if("Knockout")
			return b.instant_knockout(user, ourtarget)
		if("Cancel")
			return FALSE

/// "Health Check": Report the prey's vitality and what its state keeps it from doing.
/datum/vore_look/proc/pick_health_check(mob/user, atom/movable/target, params)
	var/mob/living/carbon/human/H = target
	var/target_health = round(H.vitality() * 100)
	var/condition
	var/condition_consequences
	to_chat(user, span_vwarning("\The [target] is at [target_health]% health."))
	if(H.blinded)
		condition += "blinded"
		condition_consequences += "hear emotes"
	if(H.has_status(STAT_PARALYZED))
		if(condition)
			condition += " and "
			condition_consequences += " or "
		condition += "paralysed"
		condition_consequences += "make emotes"
	if(H.has_status(STAT_SLEEPING))
		if(condition)
			condition += " and "
			condition_consequences += " or "
		condition += "sleeping"
		condition_consequences += "hear or do anything"
	if(condition)
		to_chat(user, span_vwarning("\The [target] is currently [condition], they will not be able to [condition_consequences]."))
	return FALSE

/datum/vore_look/proc/perform_prey_ability(datum/act/op/A, belly, ability_arg)
	var/mob/user = A.actor
	if(isnull(belly))
		return FALSE
	if(!isliving(user))
		return FALSE
	var/obj/belly/OB = belly

	if(!(user in OB))
		return TRUE // Aren't here anymore, need to update menu

	var/ability = ability_arg
	if(!(ability in list("devour_as_absorbed")))
		return FALSE

	switch(ability)
		if("devour_as_absorbed")
			if(!(OB.mode_flags & DM_FLAG_ABSORBEDVORE))
				return FALSE
			var/mob/living/living_user = user
			living_user.absorb_devour()

	return TRUE

/datum/vore_look/proc/set_spont_belly(datum/act/op/A, attribute, val)
	switch(attribute)
		if("rear")
			var/spont_target = html_encode(val)
			if(spont_target == "Current Selected")
				host().spont_belly_rear = null
			else
				host().spont_belly_rear = spont_target
			if(host().client.prefs_vr)
				host().client.prefs_vr.spont_belly_rear = host().spont_belly_rear
			unsaved_changes = TRUE
			return TRUE
		if("front")
			var/spont_target = html_encode(val)
			if(spont_target == "Current Selected")
				host().spont_belly_front = null
			else
				host().spont_belly_front = spont_target
			if(host().client.prefs_vr)
				host().client.prefs_vr.spont_belly_front = host().spont_belly_front
			unsaved_changes = TRUE
			return TRUE
		if("left")
			var/spont_target = html_encode(val)
			if(spont_target == "Current Selected")
				host().spont_belly_left = null
			else
				host().spont_belly_left = spont_target
			if(host().client.prefs_vr)
				host().client.prefs_vr.spont_belly_left = host().spont_belly_left
			unsaved_changes = TRUE
			return TRUE
		if("right")
			var/spont_target = html_encode(val)
			if(spont_target == "Current Selected")
				host().spont_belly_right = null
			else
				host().spont_belly_right = spont_target
			if(host().client.prefs_vr)
				host().client.prefs_vr.spont_belly_right = host().spont_belly_right
			unsaved_changes = TRUE
			return TRUE
	return FALSE

/datum/vore_look/proc/sanitize_fixed_list(list/messages, type, delim = "\n\n", limit)
	if(!limit)
		CRASH("[type] set message called without limit!")
	VPPREF_MESSAGE_SANITY(type)

	if(!islist(messages) || LAZYLEN(messages) != 10)
		CRASH("[type] set message lists with invalid length!")

	for(var/i = 1, i <= messages.len, i++)
		messages[i] = sanitize(messages[i], limit, FALSE, TRUE, FALSE) || ""

	switch(type)
		if(GENERAL_EXAMINE_NUTRI)
			host().nutrition_messages = messages
		if(GENERAL_EXAMINE_WEIGHT)
			host().weight_messages = messages

/// The original act_ask answer re-enters the current interactive UI's typed row.
/datum/prompt/choice/vore_reload_preferences
	timeout = 0

/datum/prompt/choice/vore_load_preferences
	parent_type = /datum/prompt/choice/vore_reload_preferences

/datum/vore_look/proc/vore_reload_preferences_apply(mob/user)
	if(!host().apply_vore_prefs())
		tgui_alert_async(user, "ERROR: " + STATION_PREF_NAME + "-specific preferences failed to apply!","Error")
	else
		to_chat(user,span_notice(STATION_PREF_NAME + "-specific preferences applied from active slot!"))
		unsaved_changes = FALSE
	return TRUE

/datum/vore_look/proc/vore_load_preferences_apply()
	// The slot is picked next; picking it applies the preferences.
	host().load_vore_prefs_from_slot()
	unsaved_changes = TRUE
	return TRUE

/// Continue the original save row with scalar answers while rereading current warning conditions.
/datum/prompt/choice/vore_save_preferences
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/vore_save_preferences/recheck_extra()
	if(QDELETED(answerer))
		return "gone"
	var/datum/tgui/original_ui = owner
	if(!istype(original_ui) || QDELETED(original_ui))
		return "gone"
	var/datum/vore_look/panel = original_ui.src_object()
	if(!istype(panel) || QDELETED(panel))
		return "gone"
	if(original_ui.status != STATUS_INTERACTIVE)
		return "not interactive"
	return null

/datum/tgui/proc/vore_save_preferences_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/list/answers = A.request.captured.Copy()
	answers[A.request.step_name] = A.answer.value
	var/datum/vore_look/panel = src_object()
	panel.vore_save_preferences_step(src, answers)

/datum/vore_look/proc/vore_save_preferences_step(datum/tgui/ui, list/answers)
	if(isnewplayer(host()))
		var/choice = answers["a1"]
		if(isnull(choice))
			open_request(ui, /datum/prompt/choice/vore_save_preferences, TYPE_PROC_REF(/datum/tgui, vore_save_preferences_answered), answerer = ui.user, step_name = "a1", captured = answers.Copy(), question = "Warning: Saving your vore panel while in the lobby will save it to the CURRENTLY LOADED character slot, and potentially overwrite it. Are you SURE you want to overwrite your current slot with these vore bellies?", title = "WARNING!", choices = list("No, abort!", "Yes, save."), buttons = TRUE)
		if(isnull(choice))
			return
		if(choice != "Yes, save.")
			return TRUE
	else if(host().real_name != host().client.prefs.read_preference(/datum/preference/name/real_name) || (!ishuman(host()) && !issilicon(host())))
		var/choice = answers["a2"]
		if(isnull(choice))
			open_request(ui, /datum/prompt/choice/vore_save_preferences, TYPE_PROC_REF(/datum/tgui, vore_save_preferences_answered), answerer = ui.user, step_name = "a2", captured = answers.Copy(), question = "Warning: Saving your vore panel while playing what is very-likely not your normal character will overwrite whatever character you have loaded in character setup. Maybe this is your 'playing a simple mob' slot, though. Are you SURE you want to overwrite your current slot with these vore bellies?", title = "WARNING!", choices = list("No, abort!", "Yes, save."), buttons = TRUE)
		if(isnull(choice))
			return
		if(choice != "Yes, save.")
			return TRUE
	// Lets check for unsavable bellies...
	var/list/unsavable_bellies = list()
	for(var/obj/belly/B in host().vore_organs)
		if(B.prevent_saving)
			unsavable_bellies += B.name
	if(LAZYLEN(unsavable_bellies))
		var/choice = answers["a3"]
		if(isnull(choice))
			open_request(ui, /datum/prompt/choice/vore_save_preferences, TYPE_PROC_REF(/datum/tgui, vore_save_preferences_answered), answerer = ui.user, step_name = "a3", captured = answers.Copy(), question = "Warning: One or more of your vore organs are unsavable. Saving now will save every vore belly except \[[jointext(unsavable_bellies, ", ")]\]. Are you sure you want to save?", title = "WARNING!", choices = list("No, abort!", "Yes, save."), buttons = TRUE)
		if(isnull(choice))
			return
		if(choice != "Yes, save.")
			return TRUE
	if(!host().save_vore_prefs())
		tgui_alert_async(ui.user, "ERROR: " + STATION_PREF_NAME + "-specific preferences failed to save!","Error")
	else
		to_chat(ui.user, span_notice(STATION_PREF_NAME + "-specific preferences saved!"))
		unsaved_changes = FALSE
	return TRUE

#undef STATION_PREF_NAME
#undef VORE_BELLY_TAB
#undef VORE_INSIDE_TAB
#undef SOULCATCHER_TAB
#undef PREFERENCE_TAB
#undef GENERAL_TAB


/// Note, we do this in case we ever want to allow people to view others vore panels (a relation view: null once it is deleted).
/datum/vore_look/proc/host() as /mob
	return host
