// *******************************************************
// Unified body transformation UI for inround TF or bodyrecord editing.
// Make a new subtype of this, and configure it for whatever changes
// that you will be allowing on the objects. This is a tgui UI and can
// be attached to any object.
//
// USE THIS instead of recoding tf/appearance editing for the forth time
// in this codebase. It should all be in one place, and extended for every
// new feature added to cosmetics. Be sure to update bodyrecords and their
// cloning/to/from mob procs as well.
//
// owner is the mob being transformed, ui.user is the mob using the interface
// if owner and user are the same, there is some special logic for self-tf.
// use can_change(owner, APPEARANCE_X) to validate if the owner is still in a
// valid state for the module to edit them.
// *******************************************************

/datum/tgui_module/appearance_changer
	name = "Appearance Editor"
	tgui_id = "AppearanceChanger"
	var/flags = APPEARANCE_ALL_HAIR
	var/tmp/mob/living/carbon/human/owner
	/// A body the designer builds for itself (owned); the owner view then names it.
	var/mob/living/carbon/human/mannequin
	var/list/valid_species
	var/list/valid_hairstyles
	var/list/valid_facial_hairstyles

	var/check_whitelist
	var/list/whitelist
	var/list/blacklist

	var/customize_usr = FALSE

	// Stuff needed to render the map
	var/map_name
	var/atom/movable/screen/map_view/cam_screen
	var/list/cam_plane_masters
	var/atom/movable/screen/background/cam_background
	var/atom/movable/screen/skybox/local_skybox
	// Stuff for moving cameras
	var/tmp/turf/last_camera_turf

	var/list/valid_earstyles
	var/list/valid_tailstyles
	var/list/valid_wingstyles
	var/list/valid_gradstyles
	var/list/markings = null
	var/cooldown //Anti-spam. If spammed, this can be REALLY laggy.

CAPABILITIES(/datum/tgui_module/appearance_changer)
	owns_one(nameof(cam_background), /atom/movable/screen/background)
	owns_one(nameof(cam_screen), /atom/movable/screen/map_view)
	owns_one(nameof(local_skybox), /atom/movable/screen/skybox)
	owns_one(nameof(mannequin), /mob/living/carbon/human)
	owns_many(nameof(cam_plane_masters))

/datum/tgui_module/appearance_changer/New(
		host,
		mob/living/carbon/human/H,
		check_species_whitelist = 1,
		list/species_whitelist = list(),
		list/species_blacklist = list())
	. = ..()

	map_name = "appearance_changer_[REF(src)]_map"
	// Initialize map objects
	rel_set(src, nameof(cam_screen), new /atom/movable/screen/map_view)

	cam_screen.name = "screen"
	cam_screen.assigned_map = map_name
	cam_screen.del_on_map_removal = FALSE
	cam_screen.screen_loc = "[map_name]:3:-32,3:-48"

	for(var/atom/movable/screen/plane_master as anything in get_tgui_plane_masters())
		rel_add(src, nameof(cam_plane_masters), plane_master)

	for(var/atom/movable/screen/instance as anything in cam_plane_masters)
		instance.assigned_map = map_name
		instance.del_on_map_removal = FALSE
		instance.screen_loc = "[map_name]:CENTER"

	rel_set(src, nameof(local_skybox), new /atom/movable/screen/skybox())
	local_skybox.assigned_map = map_name
	local_skybox.del_on_map_removal = FALSE
	local_skybox.screen_loc = "[map_name]:CENTER,CENTER"

	rel_set(src, nameof(owner), H)
	rel_set(src, nameof(cam_background), new /atom/movable/screen/background)
	cam_background.assigned_map = map_name
	cam_background.del_on_map_removal = FALSE
	check_whitelist = check_species_whitelist
	whitelist = species_whitelist
	blacklist = species_blacklist

/datum/tgui_module/appearance_changer/proc/jiggle_map()
	// Fix for weird byond bug, jiggles the map around a little
	after(src, 0.1 SECONDS, PROC_REF(jiggle_map_step), with = list(1))

/datum/tgui_module/appearance_changer/proc/jiggle_map_step(step)
	if(step == 1)
		cam_screen.screen_loc = "[map_name]:1,1"
		after(src, 0.1 SECONDS, PROC_REF(jiggle_map_step), with = list(2))
		return
	cam_screen.screen_loc = "[map_name]:3:-32,3:-48" // Align for larger icons and scales

/datum/tgui_module/appearance_changer/tgui_close(mob/user)
	. = ..()
	if(owner() == user || !customize_usr)
		close_ui()
		om_unhook(owner(), /datum/om/event/movable_attempted_move, src)
		OM_EMIT(owner(), /datum/om/event/human_dna_finalized) // Update any components using our saved appearance
		rel_clear(src, nameof(owner))
		rel_clear(src, nameof(last_camera_turf))
		cut_data()


/datum/tgui_module/appearance_changer/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!COOLDOWN_FINISHED(src, cooldown))
		to_chat(ui.user, span_warning("You are changing appearance too fast!"))
		return FALSE
	else
		COOLDOWN_START(src, cooldown, 0.5 SECONDS)
	return TRUE

UI_ACT(/datum/tgui_module/appearance_changer, "race", ui_act_race, UI_ARG_TEXT("race"))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_race)
	if(can_change(owner(), APPEARANCE_RACE) && (params["race"] in valid_species))
		// A custom species is named before the change (the answer re-runs this action).
		var/custom_name
		if(params["race"] == "Custom Species")
			custom_name = act_ask(ui.user, action, params, ui, "a1", /datum/om/prompt/text, message = "Input custom species name:", title = "Custom Species Name", max_length = MAX_NAME_LEN)
			if(isnull(custom_name))
				return
		if(owner().change_species(params["race"]))
			if(params["race"] == "Custom Species")
				owner().custom_species = custom_name
			cut_data()
			generate_data(ui.user, owner())
			changed_hook(APPEARANCECHANGER_CHANGED_RACE, user)
			return 1
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "gender", ui_act_gender, UI_ARG_VALUE("gender"))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_gender)
	if(can_change(owner(), APPEARANCE_GENDER) && (params["gender"] in get_genders(owner())))
		if(owner().change_gender(params["gender"]))
			cut_data()
			generate_data(ui.user, owner())
			changed_hook(APPEARANCECHANGER_CHANGED_GENDER, user)
			return 1
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "gender_id", ui_act_gender_id, UI_ARG_TEXT("gender_id"))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_gender_id)
	if(can_change(owner(), APPEARANCE_GENDER) && (params["gender_id"] in all_genders_define_list))
		owner().identifying_gender = params["gender_id"]
		changed_hook(APPEARANCECHANGER_CHANGED_GENDER_ID, user)
		return 1
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "skin_tone", ui_act_skin_tone)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_skin_tone)
	if(can_change_skin_tone(owner()))
		var/new_s_tone = act_ask(ui.user, action, params, ui, "a2", /datum/om/prompt/number, message = "Choose your character's skin-tone:\n(Light 1 - 220 Dark)", title = "Skin Tone", default = -owner().s_tone + 35, max = 220, min = 1)
		if(isnull(new_s_tone))
			return
		if(isnum(new_s_tone) && can_still_topic(ui.user, state))
			new_s_tone = 35 - max(min( round(new_s_tone), 220),1)
			changed_hook(APPEARANCECHANGER_CHANGED_SKINTONE, user)
			return owner().change_skin_tone(new_s_tone)
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "skin_color", ui_act_skin_color)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_skin_color)
	if(can_change_skin_color(owner()))
		ask_color(ui.user, state, "skin_color", "Skin Color", "Choose your character's skin colour: ", rgb(owner().r_skin, owner().g_skin, owner().b_skin))
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "hair", ui_act_hair, UI_ARG_VALUE("name"))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_hair)
	if(can_change(owner(), APPEARANCE_HAIR) && (params["name"] in valid_hairstyles))
		if(owner().change_hair(params["name"]))
			update_dna(owner())
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRSTYLE, user)
			return 1
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "hair_grad", ui_act_hair_grad, UI_ARG_LIST("picked"))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_hair_grad)
	var/picked = params["picked"]
	if(picked && can_change(owner(), APPEARANCE_HAIR_COLOR))
		owner().grad_style = picked[1] // returned as a list
		update_dna(owner())
		owner().regenerate_icons()
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRSTYLE, user)
		return 1
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "hair_color", ui_act_hair_color)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_hair_color)
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(ui.user, state, "hair_color", "Hair Color", "Please select hair color.", rgb(owner().r_hair, owner().g_hair, owner().b_hair))
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "hair_color_grad", ui_act_hair_color_grad)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_hair_color_grad)
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(ui.user, state, "hair_color_grad", "Hair Color", "Please select hair gradiant color.", rgb(owner().r_grad, owner().g_grad, owner().b_grad))
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "facial_hair", ui_act_facial_hair, UI_ARG_VALUE("name"))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_facial_hair)
	if(can_change(owner(), APPEARANCE_FACIAL_HAIR) && (params["name"] in valid_facial_hairstyles))
		if(owner().change_facial_hair(params["name"]))
			update_dna(owner())
			changed_hook(APPEARANCECHANGER_CHANGED_F_HAIRSTYLE, user)
			return 1
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "facial_hair_color", ui_act_facial_hair_color)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_facial_hair_color)
	if(can_change(owner(), APPEARANCE_FACIAL_HAIR_COLOR))
		ask_color(ui.user, state, "facial_hair_color", "Facial Hair Color", "Please select facial hair color.", rgb(owner().r_facial, owner().g_facial, owner().b_facial))
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "eye_color", ui_act_eye_color)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_eye_color)
	if(can_change(owner(), APPEARANCE_EYE_COLOR))
		ask_color(ui.user, state, "eye_color", "Eye Color", "Please select eye color.", rgb(owner().r_eyes, owner().g_eyes, owner().b_eyes))
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "ear", ui_act_ear, UI_ARG_VALUE("clear"), UI_ARG_REF("ref", null, /datum/sprite_accessory/ears))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_ear)
	if(can_change(owner(), APPEARANCE_ALL_HAIR))
		var/datum/sprite_accessory/ears/instance = params["ref"]
		if(params["clear"])
			instance = null
		if(!istype(instance) && !params["clear"])
			return FALSE
		owner().ear_style = instance
		owner().update_hair()
		update_dna(owner())
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRSTYLE, user)
		return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "ear_secondary", ui_act_ear_secondary, UI_ARG_VALUE("clear"), UI_ARG_REF("ref", null, /datum/sprite_accessory/ears))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_ear_secondary)
	if(can_change(owner(), APPEARANCE_ALL_HAIR))
		var/datum/sprite_accessory/ears/instance = params["ref"]
		if(params["clear"])
			instance = null
		if(!istype(instance) && !params["clear"])
			return FALSE
		owner().ear_secondary_style = instance
		if(!islist(owner().ear_secondary_colors))
			owner().ear_secondary_colors = list()
		if(instance && length(owner().ear_secondary_colors) < instance.get_color_channel_count())
			owner().ear_secondary_colors.len = instance.get_color_channel_count()
		owner().update_hair()
		update_dna(owner())
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRSTYLE, user)
		return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "ears_color", ui_act_ears_color)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_ears_color)
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(ui.user, state, "ears_color", "Ear Color", "Please select ear color.", rgb(owner().r_ears, owner().g_ears, owner().b_ears))
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "ears2_color", ui_act_ears2_color)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_ears2_color)
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(ui.user, state, "ears2_color", "2nd Ear Color", "Please select secondary ear color.", rgb(owner().r_ears2, owner().g_ears2, owner().b_ears2))
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "ears_alpha", ui_act_ears_alpha, UI_ARG_NUM("ears_alpha"))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_ears_alpha)
	var/new_alpha = clamp(params["ears_alpha"], 0, 255)
	if(isnum(new_alpha) && can_still_topic(ui.user, state))
		owner().a_ears = new_alpha
		update_dna(owner())
		owner().update_hair()
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, user)
		return 1
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "secondary_ears_alpha", ui_act_secondary_ears_alpha, UI_ARG_NUM("secondary_ears_alpha"))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_secondary_ears_alpha)
	var/new_alpha = clamp(params["secondary_ears_alpha"], 0, 255)
	if(isnum(new_alpha) && can_still_topic(ui.user, state))
		owner().a_ears2 = new_alpha
		update_dna(owner())
		owner().update_hair()
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, user)
		return 1
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "ears_secondary_color", ui_act_ears_secondary_color, UI_ARG_NUM("channel"))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_ears_secondary_color)
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		var/channel = params["channel"]
		if(channel > length(owner().ear_secondary_colors))
			return TRUE
		var/existing = LAZYACCESS(owner().ear_secondary_colors, channel) || "#ffffff"
		ask_color(ui.user, state, "ears_secondary_color", "2nd Ear Color", "Please select ear color.", existing, channel = channel)
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "tail", ui_act_tail, UI_ARG_VALUE("clear"), UI_ARG_REF("ref", null, /datum/sprite_accessory/tail))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_tail)
	if(can_change(owner(), APPEARANCE_ALL_HAIR))
		var/datum/sprite_accessory/tail/instance = params["ref"]
		if(params["clear"])
			instance = null
		if(!istype(instance) && !params["clear"])
			return FALSE
		owner().tail_style = instance
		owner().update_tail_showing()
		update_dna(owner())
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRSTYLE, user)
		return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "tail_color", ui_act_tail_color)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_tail_color)
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(ui.user, state, "tail_color", "Tail Color", "Please select tail color.", rgb(owner().r_tail, owner().g_tail, owner().b_tail))
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "tail2_color", ui_act_tail2_color)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_tail2_color)
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(ui.user, state, "tail2_color", "2nd Tail Color", "Please select secondary tail color.", rgb(owner().r_tail2, owner().g_tail2, owner().b_tail2))
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "tail3_color", ui_act_tail3_color)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_tail3_color)
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(ui.user, state, "tail3_color", "3rd Tail Color", "Please select tertiary tail color.", rgb(owner().r_tail3, owner().g_tail3, owner().b_tail3))
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "tail_alpha", ui_act_tail_alpha, UI_ARG_NUM("tail_alpha"))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_tail_alpha)
	var/new_alpha = clamp(params["tail_alpha"], 0, 255)
	if(isnum(new_alpha) && can_still_topic(ui.user, state))
		owner().a_tail = new_alpha
		update_dna(owner())
		owner().update_tail_showing()
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, user)
		return 1
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "wing", ui_act_wing, UI_ARG_VALUE("clear"), UI_ARG_REF("ref", null, /datum/sprite_accessory/wing))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_wing)
	if(can_change(owner(), APPEARANCE_ALL_HAIR))
		var/datum/sprite_accessory/wing/instance = params["ref"]
		if(params["clear"])
			instance = null
		if(!istype(instance) && !params["clear"])
			return FALSE
		owner().wing_style = instance
		owner().update_wing_showing()
		update_dna(owner())
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRSTYLE, user)
		return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "wing_color", ui_act_wing_color)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_wing_color)
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(ui.user, state, "wing_color", "Wing Color", "Please select wing color.", rgb(owner().r_wing, owner().g_wing, owner().b_wing))
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "wing2_color", ui_act_wing2_color)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_wing2_color)
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(ui.user, state, "wing2_color", "2nd Wing Color", "Please select secondary wing color.", rgb(owner().r_wing2, owner().g_wing2, owner().b_wing2))
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "wing3_color", ui_act_wing3_color)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_wing3_color)
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(ui.user, state, "wing3_color", "3rd Wing Color", "Please select tertiary wing color.", rgb(owner().r_wing3, owner().g_wing3, owner().b_wing3))
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "wing_alpha", ui_act_wing_alpha, UI_ARG_NUM("wing_alpha"))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_wing_alpha)
	var/new_alpha = clamp(params["wing_alpha"], 0, 255)
	if(isnum(new_alpha) && can_still_topic(ui.user, state))
		owner().a_wing = new_alpha
		update_dna(owner())
		owner().update_wing_showing()
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, user)
		return 1
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "marking", ui_act_marking, UI_ARG_TEXT("name"), UI_ARG_NUM("todo"))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_marking)
	if(can_change(owner(), APPEARANCE_ALL_HAIR))
		var/todo = params["todo"]
		var/name_marking = params["name"]
		switch (todo)
			if (0) //delete
				if (name_marking)
					var/datum/sprite_accessory/marking/mark_datum = GLOB.body_marking_styles_list[name_marking]
					if (owner().remove_marking(mark_datum))
						changed_hook(APPEARANCECHANGER_CHANGED_HAIRSTYLE, user)
						return TRUE
			if (1) //add
				if(name_marking && can_still_topic(ui.user, state))
					var/datum/sprite_accessory/marking/mark_datum = GLOB.body_marking_styles_list[name_marking]
					if (owner().add_marking(mark_datum))
						changed_hook(APPEARANCECHANGER_CHANGED_HAIRSTYLE, user)
						return TRUE
			if (2) //move up
				var/datum/sprite_accessory/marking/mark_datum = GLOB.body_marking_styles_list[name_marking]
				if (owner().change_priority_of_marking(mark_datum, FALSE))
					return TRUE
			if (3) //move down
				var/datum/sprite_accessory/marking/mark_datum = GLOB.body_marking_styles_list[name_marking]
				if (owner().change_priority_of_marking(mark_datum, TRUE))
					return TRUE
			if (4) //color
				var/current = markings[name_marking] ? markings[name_marking]["color"] : "#000000"
				ask_color(ui.user, state, "marking", "Marking color", "Please select marking color", current, marking_name = name_marking)
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "rotate_view", ui_act_rotate_view)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_rotate_view)
	owner().set_dir(turn(owner().dir, 90))
	return TRUE

UI_ACT(/datum/tgui_module/appearance_changer, "rename", ui_act_rename)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_rename)
	if(owner())
		var/raw_name = act_ask(ui.user, action, params, ui, "a3", /datum/om/prompt/text, message = "Choose the a name:", title = "Sleeve Name", encode = FALSE)
		if(isnull(raw_name))
			return
		if(!isnull(raw_name) && can_change(owner(), APPEARANCE_RACE))
			var/new_name = sanitize_name(raw_name, owner().species, FALSE) // can't edit synths
			if(new_name)
				owner().dna.real_name = new_name
				owner().real_name = new_name
				owner().name = new_name
				return TRUE
			else
				to_chat(ui.user, span_warning("Invalid name. Your name should be at least 2 and at most [MAX_NAME_LEN] characters long. It may only contain the characters A-Z, a-z, -, ' and ."))
				return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "char_name", ui_act_char_name)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_char_name)
	var/obj/machinery/computer/transhuman/designer/DC = null
	var/datum/tgui_module/appearance_changer/body_designer/BD = null
	if(istype(src,/datum/tgui_module/appearance_changer/body_designer))
		BD = src
		DC = BD.linked_body_design_console
	if(DC) // Only body designer does this. no hrefing
		var/new_name = act_ask(ui.user, action, params, ui, "a4", /datum/om/prompt/text, message = "Input character's name:", title = "Name", default = owner().name, max_length = MAX_NAME_LEN)
		if(isnull(new_name))
			return
		if(can_change(owner(), APPEARANCE_RACE)) // new name can be empty, it uses base species if so
			owner().name = new_name
			owner().real_name = owner().name
			owner().dna.real_name = owner().name
			return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "race_name", ui_act_race_name)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_race_name)
	var/new_name = act_ask(ui.user, action, params, ui, "a5", /datum/om/prompt/text, message = "Input custom species name:", title = "Custom Species Name", default = owner().custom_species, max_length = MAX_NAME_LEN)
	if(isnull(new_name))
		return
	if(can_change(owner(), APPEARANCE_RACE)) // new name can be empty, it uses base species if so
		owner().custom_species = new_name
		return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "base_icon", ui_act_base_icon)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_base_icon)
	if(can_change(owner(), APPEARANCE_MISC))
		var/new_species = act_ask(ui.user, action, params, ui, "a6", /datum/om/prompt/choice, message = "Please select basic shape.", title = "Body Shape", choices = GLOB.custom_species_bases)
		if(isnull(new_species))
			return
		if(new_species)
			// species is PROTO: mutate the mob's private copy, never the shared prototype
			var/datum/species/own_species = proto_private(owner(), nameof(/datum/dna::species))
			own_species.base_species = new_species
			own_species.icobase = own_species.get_icobase()
			own_species.deform = own_species.get_icobase(get_deform = TRUE)
			own_species.vanity_base_fit = new_species
			if(istype(owner().species, /datum/species/shapeshifter)) //TODO: See if this is still needed.
				GLOB.wrapped_species_by_ref["\ref[owner()]"] = new_species
			owner().regenerate_icons()
			generate_data(ui.user, owner())
			changed_hook(APPEARANCECHANGER_CHANGED_RACE, user)
			return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "blood_reagent", ui_act_blood_reagent)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_blood_reagent)
	if(can_change(owner(), APPEARANCE_MISC))
		var/new_blood_reagents = act_ask(ui.user, action, params, ui, "a7", /datum/om/prompt/choice, message = "Please select blood restoration reagent:", title = "Character Preference", choices = GLOB.valid_bloodreagents)
		if(isnull(new_blood_reagents))
			return
		if(new_blood_reagents)
			owner().dna.blood_reagents = new_blood_reagents
			changed_hook(APPEARANCECHANGER_CHANGED_RACE, user)
			return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "blood_color", ui_act_blood_color)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_blood_color)
	var/current = owner().species.blood_color ? owner().species.blood_color : "#A10808"
	ask_color(ui.user, state, "blood_color", "Blood color", "Please select blood color", current)
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "weight", ui_act_weight)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_weight)
	var/new_weight = act_ask(ui.user, action, params, ui, "a8", /datum/om/prompt/number, message = "Choose tbe character's relative body weight.\nThis measurement should be set relative to a normal 5'10'' person's body and not the actual size of the character.\n([WEIGHT_MIN]-[WEIGHT_MAX])", title = "Character Preference", max = WEIGHT_MAX, min = WEIGHT_MIN, round_entry = FALSE)
	if(isnull(new_weight))
		return
	if(new_weight && can_change(owner(), APPEARANCE_MISC))
		var/unit_of_measurement = act_ask(ui.user, action, params, ui, "a9", /datum/om/prompt/choice/alert, message = "Is that number in pounds (lb) or kilograms (kg)?", title = "Confirmation", choices = list("Pounds", "Kilograms"))
		if(isnull(unit_of_measurement))
			return
		if(unit_of_measurement)
			if(unit_of_measurement == "Pounds")
				new_weight = round(text2num(new_weight),4)
			if(unit_of_measurement == "Kilograms")
				new_weight = round(2.20462*text2num(new_weight),4)
			owner().weight = sanitize_integer(new_weight, WEIGHT_MIN, WEIGHT_MAX, owner().weight)
			changed_hook(APPEARANCECHANGER_CHANGED_RACE, user)
			return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "size_scale", ui_act_size_scale)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_size_scale)
	var/new_size = act_ask(ui.user, action, params, ui, "a10", /datum/om/prompt/number, message = "Choose size, ranging from [RESIZE_MINIMUM * 100]% to [RESIZE_MAXIMUM * 100]%", title = "Set Size", max = RESIZE_MAXIMUM * 100, min = RESIZE_MINIMUM * 100)
	if(isnull(new_size))
		return
	if(new_size && ISINRANGE(new_size,RESIZE_MINIMUM * 100,RESIZE_MAXIMUM * 100) && can_change(owner(), APPEARANCE_MISC))
		owner().resize(new_size / 100, animate = FALSE, ignore_prefs = TRUE)
		owner().regenerate_icons()
		owner().set_dir(owner().dir) // Causes a visual update for fuzzy/offset
		changed_hook(APPEARANCECHANGER_CHANGED_RACE, user)
		return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "scale_appearance", ui_act_scale_appearance)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_scale_appearance)
	if(can_change(owner(), APPEARANCE_MISC))
		owner().dna.scale_appearance = !owner().dna.scale_appearance
		owner().fuzzy = owner().dna.scale_appearance
		owner().regenerate_icons()
		owner().set_dir(owner().dir) // Causes a visual update for fuzzy/offset
		return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "offset_override", ui_act_offset_override)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_offset_override)
	if(can_change(owner(), APPEARANCE_MISC))
		owner().dna.offset_override = !owner().dna.offset_override
		owner().offset_override = owner().dna.offset_override
		owner().regenerate_icons()
		owner().set_dir(owner().dir) // Causes a visual update for fuzzy/offset
		return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "digitigrade", ui_act_digitigrade)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_digitigrade)
	if(can_change(owner(), APPEARANCE_MISC))
		owner().dna.digitigrade = !owner().dna.digitigrade
		owner().digitigrade = owner().dna.digitigrade
		owner().regenerate_icons()
		generate_data(ui.user, owner())
		changed_hook(APPEARANCECHANGER_CHANGED_RACE, user)
		return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "species_sound", ui_act_species_sound)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_species_sound)
	var/list/possible_species_sound_types = GLOB.species_sound_map
	var/choice = act_ask(ui.user, action, params, ui, "a11", /datum/om/prompt/choice, message = "Which set of sounds would you like to use? (Cough, Sneeze, Scream, Pain, Gasp, Death)", title = "Species Sounds", choices = possible_species_sound_types)
	if(isnull(choice))
		return
	if(choice && can_change(owner(), APPEARANCE_MISC))
		var/datum/species/own_species = proto_private(owner(), nameof(/datum/dna::species)) // PROTO: private copy
		own_species.species_sounds = choice
		return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "flavor_text", ui_act_flavor_text, UI_ARG_TEXT("target"))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_flavor_text)
	var/select_key = params["target"]
	if(select_key && can_change(owner(), APPEARANCE_MISC))
		if(select_key in owner().flavor_texts)
			switch(select_key)
				if("general")
					var/_answer_a12 = act_ask(ui.user, action, params, ui, "a12", /datum/om/prompt/text, message = "Give a general description of the character. This will be shown regardless of clothings. Put in \"!clear\" to make blank.", title = "Flavor Text", default = html_decode(owner().flavor_texts[select_key]), multiline = TRUE, max_length = MAX_TGUI_INPUT)
					if(isnull(_answer_a12))
						return
					var/msg = strip_html_simple(_answer_a12)
					if(can_change(owner(), APPEARANCE_MISC)) // allows empty to wipe flavor
						if(msg == "!clear")
							msg = ""
						var/mob/living/carbon/human/flavor_owner = owner()
						LAZYSET(flavor_owner.flavor_texts, select_key, msg)
						return TRUE
				else
					var/_answer_a13 = act_ask(ui.user, action, params, ui, "a13", /datum/om/prompt/text, message = "Set the flavor text for their [select_key]. Put in \"!clear\" to make blank.", title = "Flavor Text", default = html_decode(owner().flavor_texts[select_key]), multiline = TRUE, max_length = MAX_TGUI_INPUT)
					if(isnull(_answer_a13))
						return
					var/msg = strip_html_simple(_answer_a13)
					if(can_change(owner(), APPEARANCE_MISC)) // allows empty to wipe flavor
						if(msg == "!clear")
							msg = ""
						var/mob/living/carbon/human/flavor_owner = owner()
						LAZYSET(flavor_owner.flavor_texts, select_key, msg)
						return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "load_saveslot", ui_act_load_saveslot)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_load_saveslot)
	if(can_change(owner(), APPEARANCE_ALL_COSMETIC))
		var/_answer_a14 = act_ask(owner(), action, params, ui, "a14", /datum/om/prompt/choice/alert, message = "Are you certain you wish to load the currently selected savefile?", title = "Load Savefile", choices = list("No","Yes"))
		if(isnull(_answer_a14))
			return
		if(_answer_a14 == "Yes")
			if(owner() && owner().client) //sanity
				owner().client.prefs.vanity_copy_to(owner(), FALSE, TRUE, FALSE, FALSE, FALSE)
				return TRUE
			return TRUE
		else
			return TRUE
// ***********************************
// Body designer UI
// ***********************************
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "view_brec", ui_act_view_brec, UI_ARG_REF("view_brec", null, /datum/transhuman/body_record))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_view_brec)
	var/obj/machinery/computer/transhuman/designer/DC = null
	var/datum/tgui_module/appearance_changer/body_designer/BD = null
	if(istype(src,/datum/tgui_module/appearance_changer/body_designer))
		BD = src
		DC = BD.linked_body_design_console
	var/datum/transhuman/body_record/BR = params["view_brec"]
	if(BR && istype(BR.mydna))
		if(DC.allowed(ui.user) || BR.ckey == ui.user.ckey)
			BD.load_record_to_body(BR)
			owner().resleeve_lock = BR.locked
			owner().changeling_locked = BR.changeling_locked
			DC.selected_record = TRUE
	return TRUE

UI_ACT(/datum/tgui_module/appearance_changer, "view_stock_brec", ui_act_view_stock_brec, UI_ARG_TEXT("view_stock_brec"))
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_view_stock_brec)
	var/obj/machinery/computer/transhuman/designer/DC = null
	var/datum/tgui_module/appearance_changer/body_designer/BD = null
	if(istype(src,/datum/tgui_module/appearance_changer/body_designer))
		BD = src
		DC = BD.linked_body_design_console
	var/datum/species/S = GLOB.all_species[params["view_stock_brec"]]
	if(S && (S.spawn_flags & (SPECIES_IS_WHITELISTED|SPECIES_CAN_JOIN)) == SPECIES_CAN_JOIN)
		// Generate body record from species!
		own_clear(src, nameof(/datum/tgui_module/appearance_changer::mannequin), OWN_DELETE)
		rel_set(src, nameof(/datum/tgui_module/appearance_changer::mannequin), new /mob/living/carbon/human(null, S.name))
		rel_set(src, nameof(/datum/action_group::owner), mannequin)
		owner().real_name = "Stock [S.name] Body"
		owner().name = owner().real_name
		owner().dna.real_name = owner().real_name
		owner().dna.base_species = S.base_species
		owner().resleeve_lock = FALSE
		owner().custom_species = "Custom Sleeve" // Custom name
		DC.selected_record = TRUE
	return TRUE

UI_ACT(/datum/tgui_module/appearance_changer, "loadfromdisk", ui_act_loadfromdisk)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_loadfromdisk)
	var/obj/machinery/computer/transhuman/designer/DC = null
	var/datum/tgui_module/appearance_changer/body_designer/BD = null
	if(istype(src,/datum/tgui_module/appearance_changer/body_designer))
		BD = src
		DC = BD.linked_body_design_console
	if(!DC.disk)
		return FALSE
	if(DC.disk.stored && can_change(owner(), APPEARANCE_RACE))
		BD.load_record_to_body(DC.disk.stored)
		DC.selected_record = TRUE
		to_chat(ui.user,span_notice("\The [owner()]'s bodyrecord was loaded from the disk."))
	return TRUE

UI_ACT(/datum/tgui_module/appearance_changer, "savetodisk", ui_act_savetodisk)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_savetodisk)
	var/obj/machinery/computer/transhuman/designer/DC = null
	var/datum/tgui_module/appearance_changer/body_designer/BD = null
	if(istype(src,/datum/tgui_module/appearance_changer/body_designer))
		BD = src
		DC = BD.linked_body_design_console
	if(!DC.selected_record)
		return FALSE
	if(!DC.disk)
		return FALSE
	if(owner().changeling_locked)
		to_chat(ui.user, span_warning("ERROR: Record too complex. Disk does not have enough space to store this record."))
	else if(owner().resleeve_lock)
		var/answer = act_ask(ui.user, action, params, ui, "a15", /datum/om/prompt/choice/alert, message = "This body record will be written to a disk and allow any mind to inhabit it. This is against the current body owner's configured OOC preferences for body impersonation. Please confirm that you have permission to do this, and are sure! Admins will be notified.", title = "Mind Compatability", choices = list("No","Yes"))
		if(isnull(answer))
			return
		if(!answer)
			return
		if(answer == "No")
			to_chat(ui.user, span_warning("ERROR: This body record is restricted."))
		else
			message_admins("[ui.user] wrote an unlocked version of [owner().real_name]'s bodyrecord to a disk. Their preferences do not allow body impersonation, but may be allowed with OOC consent.")
			owner().resleeve_lock = FALSE // unlock it, even though it's only temp, so you don't get the warning every time
	if(!owner().changeling_locked && (!owner().resleeve_lock && can_change(owner(), APPEARANCE_RACE)))
		// Create it from the mob
		to_chat(ui.user,span_notice("\The [owner()]'s bodyrecord was saved to the disk."))
		owner().update_dna()
		var/datum/transhuman/body_record/record = new /datum/transhuman/body_record(owner(), FALSE, FALSE) // Saves a COPY! The old record is deleted
		record.locked = FALSE // remove lock
		own_set(DC.disk, nameof(/datum/stored_item::stored), record)
		DC.disk.name = "[initial(DC.disk.name)] ([owner().real_name])"
	return TRUE

UI_ACT(/datum/tgui_module/appearance_changer, "ejectdisk", ui_act_ejectdisk)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_ejectdisk)
	var/obj/machinery/computer/transhuman/designer/DC = null
	var/datum/tgui_module/appearance_changer/body_designer/BD = null
	if(istype(src,/datum/tgui_module/appearance_changer/body_designer))
		BD = src
		DC = BD.linked_body_design_console
	if(!DC.disk)
		return FALSE
	if(can_change(owner(), APPEARANCE_RACE))
		to_chat(ui.user,span_notice("You eject the disk."))
		DC.disk.forceMove(get_turf(DC))
		own_take(DC, nameof(/obj/machinery/computer/scan_consolenew::disk))
		return TRUE
	return FALSE

UI_ACT(/datum/tgui_module/appearance_changer, "back_to_library", ui_act_back_to_library)
UI_ACT_PROC(/datum/tgui_module/appearance_changer, ui_act_back_to_library)
	var/obj/machinery/computer/transhuman/designer/DC = null
	var/datum/tgui_module/appearance_changer/body_designer/BD = null
	if(istype(src,/datum/tgui_module/appearance_changer/body_designer))
		BD = src
		DC = BD.linked_body_design_console
	if(can_change(owner(), APPEARANCE_RACE))
		BD.make_fake_owner()
		DC.selected_record = FALSE
		return TRUE
	return FALSE

/datum/tgui_module/appearance_changer/ui_prepare(mob/user, datum/tgui/ui)
	if(customize_usr && !owner())
		if(!ishuman(user))
			return FALSE
		rel_set(src, nameof(owner), user)
	if(!owner() || !owner().species)
		return FALSE
	update_active_camera_screen()
	return ..()

/datum/tgui_module/appearance_changer/ui_opening(mob/user, datum/tgui/ui)
	..()
	dq_add_recursive_move(owner())
	om_hook(owner(), /datum/om/event/movable_attempted_move, src, PROC_REF(update_active_camera_screen))
	// Register map objects
	user.client.register_map_obj(cam_screen)
	for(var/plane in cam_plane_masters)
		user.client.register_map_obj(plane)
	user.client.register_map_obj(local_skybox) // owned via local_skybox, not the plane list
	user.client.register_map_obj(cam_background)

/datum/tgui_module/appearance_changer/ui_opened(mob/user, datum/tgui/ui)
	..()
	jiggle_map()

/datum/tgui_module/appearance_changer/tgui_static_data(mob/user)
	var/list/data = ..()

	generate_data(user, owner())

	if(can_change(owner(), APPEARANCE_RACE))
		var/species[0]
		for(var/specimen in valid_species)
			species[++species.len] =  list("specimen" = specimen)
		data["species"] = species

	if(can_change(owner(), APPEARANCE_HAIR))
		var/hair_styles[0]
		for(var/hair_style in valid_hairstyles)
			var/datum/sprite_accessory/hair/S = GLOB.hair_styles_list[hair_style]
			hair_styles[++hair_styles.len] = list("name" = hair_style, "icon" = S.icon, "icon_state" = "[S.icon_state]_s")
		data["hair_styles"] = hair_styles
		data["ear_styles"] = (valid_earstyles || list())
		data["tail_styles"] = (valid_tailstyles || list())
		data["wing_styles"] = (valid_wingstyles || list())

		markings = owner().get_prioritised_markings()
		var/list/usable_markings = markings.Copy() ^ GLOB.body_marking_styles_list.Copy()
		var/marking_styles[0]
		for(var/marking_style in usable_markings)
			if(marking_style == DEVELOPER_WARNING_NAME)
				continue
			var/datum/sprite_accessory/marking/S = GLOB.body_marking_styles_list[marking_style]
			var/our_iconstate = S.icon_state
			if(LAZYLEN(S.body_parts))
				our_iconstate += "-[S.body_parts[1]]"
			marking_styles[++marking_styles.len] = list("name" = marking_style, "icon" = S.icon, "icon_state" = "[our_iconstate]")
		data["marking_styles"] = marking_styles

	if(can_change(owner(), APPEARANCE_FACIAL_HAIR))
		var/facial_hair_styles[0]
		for(var/facial_hair_style in valid_facial_hairstyles)
			var/datum/sprite_accessory/facial_hair/S = GLOB.facial_hair_styles_list[facial_hair_style]
			facial_hair_styles[++facial_hair_styles.len] = list("name" = facial_hair_style, "icon" = S.icon, "icon_state" = "[S.icon_state]_s")
		data["facial_hair_styles"] = facial_hair_styles

	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		data["hair_grads"] = (valid_gradstyles || list())

	data["mapRef"] = map_name

	return data

UI_DATA(/datum/tgui_module/appearance_changer, "merge:ui_data_datum_tgui_module_appearance_changer{is_design_console:bool,disk:bool,selected_a_record:num,character_records:list,stock_records:list,change_race:unknown,change_misc:unknown,gender_id:unknown,change_gender:unknown,change_hair:unknown,change_eye_color:unknown,change_hair_color:unknown,change_facial_hair_color:unknown,species_name:unknown,use_custom_icon:bool,base_icon:unknown,synthetic:text,size_scale:text,scale_appearance:text,offset_override:text,weight:num,digitigrade:num,blood_reagent:text,blood_color:text,species_sound:text,species_sounds_gendered:num,species_sounds_female:text,species_sounds_male:text,flavor_text:unknown,name:text,specimen:text,gender:unknown,saveslot_load:unknown,genders:list,id_genders:unknown,hair_style:text,ear_style:unknown,ear_secondary_style:text,tail_style:unknown,wing_style:unknown,markings:unknown,change_facial_hair:unknown,facial_hair_style:text,change_skin_tone:unknown,change_skin_color:unknown,skin_color:text,eye_color:text,hair_color:text,hair_color_grad:text,ears_color:text,ears2_color:text,hair_grad:text,ear_secondary_colors:bool,tail_color:text,tail2_color:text,tail3_color:text,wing_color:text,wing2_color:text,wing3_color:text,wing_alpha:num,tail_alpha:num,ears_alpha:num,secondary_ears_alpha:num,facial_hair_color:text}")

/// The computed part of /datum/tgui_module/appearance_changer's window data (declared on its UI_DATA row).
/datum/tgui_module/appearance_changer/proc/ui_data_datum_tgui_module_appearance_changer(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	generate_data(user, owner())

	data["is_design_console"] = FALSE
	data["disk"] = FALSE
	data["selected_a_record"] = FALSE
	data["character_records"] = list()
	data["stock_records"] = list()
	// Handle some unique stuff to the body design console
	var/obj/machinery/computer/transhuman/designer/DC = null
	if(istype(src,/datum/tgui_module/appearance_changer/body_designer))
		var/datum/tgui_module/appearance_changer/body_designer/BD = src
		DC = BD.linked_body_design_console
	if(DC)
		data["is_design_console"] = TRUE
		data["disk"] = !isnull(DC.disk)
		// Monkey is a placeholder, because I am not hackcoding the appearance changer to accept a null owner - Willbird
		data["selected_a_record"] = DC.selected_record
		if(!DC.selected_record)
			// Load all records on station that can be printed
			var/list/bodyrecords_list_ui = list()
			for(var/N in DC.our_db().body_scans)
				var/datum/transhuman/body_record/BR = DC.our_db().body_scans[N]
				var/datum/species/S = GLOB.all_species[BR.mydna.dna.species]
				if((S.spawn_flags & (SPECIES_IS_WHITELISTED|SPECIES_CAN_JOIN)) != SPECIES_CAN_JOIN || BR.synthetic) continue
				bodyrecords_list_ui[++bodyrecords_list_ui.len] = list("name" = N, "recref" = "\ref[BR]")
			data["character_records"] = bodyrecords_list_ui
			// Load all stock records printable
			var/list/stock_bodyrecords_list_ui = list()
			for (var/N in GLOB.all_species)
				var/datum/species/S = GLOB.all_species[N]
				if((S.spawn_flags & (SPECIES_IS_WHITELISTED|SPECIES_CAN_JOIN)) != SPECIES_CAN_JOIN) continue
				stock_bodyrecords_list_ui += N
			data["stock_records"] = stock_bodyrecords_list_ui
			data["change_race"] = can_change(owner(), APPEARANCE_RACE)
			data["change_misc"] = can_change(owner(), APPEARANCE_MISC)
			data["gender_id"] = can_change(owner(), APPEARANCE_GENDER)
			data["change_gender"] = can_change(owner(), APPEARANCE_GENDER)
			data["change_hair"] = can_change(owner(), APPEARANCE_HAIR)
			data["change_eye_color"] = can_change(owner(), APPEARANCE_EYE_COLOR)
			data["change_hair_color"] = can_change(owner(), APPEARANCE_HAIR_COLOR)
			data["change_facial_hair_color"] = can_change(owner(), APPEARANCE_FACIAL_HAIR_COLOR)
			// Drop out early, as we have nothing to edit, and are on the BR menu for the designer
			return data
	// species/body
	data["species_name"] = owner().custom_species
	data["use_custom_icon"] = (owner().species.selects_bodytype >= SELECTS_BODYTYPE_CUSTOM)
	data["base_icon"] = owner().species.base_species
	data["synthetic"] = owner().synthetic ? "Yes" : "No"
	data["size_scale"] = player_size_name(owner().size_multiplier)
	data["scale_appearance"] = owner().dna.scale_appearance ? "Fuzzy" : "Sharp"
	data["offset_override"] = owner().dna.offset_override ? "Odd" : "Even"
	data["weight"] = owner().weight
	data["digitigrade"] = owner().digitigrade
	data["blood_reagent"] = owner().dna.blood_reagents
	data["blood_color"] = owner().dna.blood_color
	data["species_sound"] = owner().species.species_sounds
	// Are these needed? It seems to be only used if above is unset??
	data["species_sounds_gendered"] = owner().species.gender_specific_species_sounds
	data["species_sounds_female"] = owner().species.species_sounds_female
	data["species_sounds_male"] = owner().species.species_sounds_male
	// flavor
	var/mob/living/carbon/human/flavor_owner = owner()
	if(!LAZYLEN(flavor_owner.flavor_texts))
		LAZYSET(flavor_owner.flavor_texts, "general", "")
		LAZYSET(flavor_owner.flavor_texts, "head", "")
		LAZYSET(flavor_owner.flavor_texts, "face", "")
		LAZYSET(flavor_owner.flavor_texts, "eyes", "")
		LAZYSET(flavor_owner.flavor_texts, "torso", "")
		LAZYSET(flavor_owner.flavor_texts, "arms", "")
		LAZYSET(flavor_owner.flavor_texts, "hands", "")
		LAZYSET(flavor_owner.flavor_texts, "legs", "")
		LAZYSET(flavor_owner.flavor_texts, "feet", "")
	data["flavor_text"] = owner().flavor_texts.Copy()

	data["name"] = owner().name
	data["specimen"] = owner().species.name
	data["gender"] = owner().gender
	data["gender_id"] = owner().identifying_gender //This is saved to your MIND.
	data["change_race"] = can_change(owner(), APPEARANCE_RACE)
	data["saveslot_load"] = can_change(owner(), APPEARANCE_ALL_COSMETIC)
	data["change_misc"] = can_change(owner(), APPEARANCE_MISC)

	data["change_gender"] = can_change(owner(), APPEARANCE_GENDER)
	if(data["change_gender"])
		var/genders[0]
		for(var/gender in get_genders(owner()))
			genders[++genders.len] =  list("gender_name" = gender2text(gender), "gender_key" = gender)
		data["genders"] = genders
		var/id_genders[0]
		for(var/gender in all_genders_define_list)
			id_genders[++id_genders.len] =  list("gender_name" = gender2text(gender), "gender_key" = gender)
		data["id_genders"] = id_genders

	data["change_hair"] = can_change(owner(), APPEARANCE_HAIR)
	if(data["change_hair"])
		data["hair_style"] = owner().h_style

		data["ear_style"] = owner().ear_style
		data["ear_secondary_style"] = owner().ear_secondary_style?.name
		data["tail_style"] = owner().tail_style
		data["wing_style"] = owner().wing_style
		var/list/markings_data[0]
		markings = owner().get_prioritised_markings()
		for (var/marking in markings)
			markings_data[++markings_data.len] = list("marking_name" = marking, "marking_color" = markings[marking]["color"] ? markings[marking]["color"] : "#000000") //too tired to add in another submenu for bodyparts here
		data["markings"] = markings_data

	data["change_facial_hair"] = can_change(owner(), APPEARANCE_FACIAL_HAIR)
	if(data["change_facial_hair"])
		data["facial_hair_style"] = owner().f_style

	data["change_skin_tone"] = can_change_skin_tone(owner())
	data["change_skin_color"] = can_change_skin_color(owner())
	if(data["change_skin_color"])
		data["skin_color"] = rgb(owner().r_skin, owner().g_skin, owner().b_skin)

	data["change_eye_color"] = can_change(owner(), APPEARANCE_EYE_COLOR)
	if(data["change_eye_color"])
		data["eye_color"] = rgb(owner().r_eyes, owner().g_eyes, owner().b_eyes)

	data["change_hair_color"] = can_change(owner(), APPEARANCE_HAIR_COLOR)
	if(data["change_hair_color"])
		data["hair_color"] = rgb(owner().r_hair, owner().g_hair, owner().b_hair)
		data["hair_color_grad"] = rgb(owner().r_grad, owner().g_grad, owner().b_grad)
		data["ears_color"] = rgb(owner().r_ears, owner().g_ears, owner().b_ears)
		data["ears2_color"] = rgb(owner().r_ears2, owner().g_ears2, owner().b_ears2)

		// not a color, but it basically is
		data["hair_grad"] = owner().grad_style

		// secondary ear colors
		var/list/ear_secondary_color_channels = owner().ear_secondary_colors || list()
		ear_secondary_color_channels.len = owner().ear_secondary_style?.get_color_channel_count() || 0
		data["ear_secondary_colors"] = ear_secondary_color_channels

		data["tail_color"] = rgb(owner().r_tail, owner().g_tail, owner().b_tail)
		data["tail2_color"] = rgb(owner().r_tail2, owner().g_tail2, owner().b_tail2)
		data["tail3_color"] = rgb(owner().r_tail3, owner().g_tail3, owner().b_tail3)
		data["wing_color"] = rgb(owner().r_wing, owner().g_wing, owner().b_wing)
		data["wing2_color"] = rgb(owner().r_wing2, owner().g_wing2, owner().b_wing2)
		data["wing3_color"] = rgb(owner().r_wing3, owner().g_wing3, owner().b_wing3)
		data["wing_alpha"] = owner().a_wing
		data["tail_alpha"] = owner().a_tail
		data["ears_alpha"] = owner().a_ears
		data["secondary_ears_alpha"] = owner().a_ears2

	data["change_facial_hair_color"] = can_change(owner(), APPEARANCE_FACIAL_HAIR_COLOR)
	if(data["change_facial_hair_color"])
		data["facial_hair_color"] = rgb(owner().r_facial, owner().g_facial, owner().b_facial)
	return data

/datum/tgui_module/appearance_changer/proc/update_active_camera_screen(datum/source, datum/om/event/movable_attempted_move/event)
	EVENT_HANDLER
	cam_screen.vis_contents = list(owner()) // Copied from the vore version.
	cam_background.icon_state = "clear"
	cam_background.fill_rect(1, 1, 1, 1)
	local_skybox.cut_overlays()

/datum/tgui_module/appearance_changer/proc/update_dna(mob/living/carbon/human/target)
	if(target)
		target.update_dna()

/datum/tgui_module/appearance_changer/proc/can_change(mob/living/carbon/human/target, flag)
	return target && (flags & flag)

/datum/tgui_module/appearance_changer/proc/can_change_skin_tone(mob/living/carbon/human/target)
	return target && (flags & APPEARANCE_SKIN) &&target.species.appearance_flags & HAS_SKIN_TONE

/datum/tgui_module/appearance_changer/proc/can_change_skin_color(mob/living/carbon/human/target)
	return target && (flags & APPEARANCE_SKIN) && target.species.appearance_flags & HAS_SKIN_COLOR

/datum/tgui_module/appearance_changer/proc/cut_data()
	// Making the assumption that the available species remain constant
	LAZYCLEARLIST(valid_hairstyles)
	LAZYCLEARLIST(valid_facial_hairstyles)
	LAZYCLEARLIST(valid_earstyles)
	LAZYCLEARLIST(valid_tailstyles)
	LAZYCLEARLIST(valid_wingstyles)
	LAZYCLEARLIST(valid_gradstyles)

/datum/tgui_module/appearance_changer/proc/generate_data(mob/user, mob/living/carbon/human/target)
	if(!ishuman(target))
		return TRUE

	if(!LAZYLEN(valid_species))
		valid_species = target.generate_valid_species(check_whitelist, whitelist, blacklist)

	if(!LAZYLEN(valid_hairstyles) || !LAZYLEN(valid_facial_hairstyles))
		valid_hairstyles = target.generate_valid_hairstyles(check_gender = 0)
		valid_facial_hairstyles = target.generate_valid_facial_hairstyles()

	if(!LAZYLEN(valid_earstyles))
		for(var/path in GLOB.ear_styles_list)
			var/datum/sprite_accessory/ears/instance = GLOB.ear_styles_list[path]
			if(can_use_sprite(instance, target, user))
				LAZYINITLIST(valid_earstyles); valid_earstyles.Add(list(list(
					"name" = instance.name,
					"instance" = REF(instance),
					"color" = !!instance.do_colouration,
					"second_color" = !!instance.extra_overlay,
					"icon" = instance.icon,
					"icon_state" = instance.icon_state
				)))

	if(!LAZYLEN(valid_tailstyles))
		for(var/path in GLOB.tail_styles_list)
			var/datum/sprite_accessory/tail/instance = GLOB.tail_styles_list[path]
			if(can_use_sprite(instance, target, user))
				LAZYINITLIST(valid_tailstyles); valid_tailstyles.Add(list(list(
					"name" = instance.name,
					"instance" = REF(instance),
					"color" = !!instance.do_colouration,
					"second_color" = !!instance.extra_overlay,
					"icon" = instance.icon,
					"icon_state" = instance.icon_state
				)))

	if(!LAZYLEN(valid_wingstyles))
		for(var/path in GLOB.wing_styles_list)
			var/datum/sprite_accessory/wing/instance = GLOB.wing_styles_list[path]
			if(can_use_sprite(instance, target, user))
				LAZYINITLIST(valid_wingstyles); valid_wingstyles.Add(list(list(
					"name" = instance.name,
					"instance" = REF(instance),
					"color" = !!instance.do_colouration,
					"second_color" = !!instance.extra_overlay,
					"icon" = instance.icon,
					"icon_state" = instance.icon_state
				)))

	if(!LAZYLEN(valid_gradstyles))
		for(var/key in GLOB.hair_gradients)
			LAZYADD(valid_gradstyles, list(list(key)))

/datum/tgui_module/appearance_changer/proc/get_genders(mob/living/carbon/human/target)
	var/datum/species/S = target.species
	var/list/possible_genders = S.genders
	if(!target.organ_in("cell"))
		return possible_genders
	possible_genders = possible_genders.Copy()
	possible_genders |= NEUTER
	return possible_genders

// Used for subtypes to handle messaging or whatever.
/datum/tgui_module/appearance_changer/proc/changed_hook(flag, mob/user)
	return

/datum/tgui_module/appearance_changer/proc/can_use_sprite(datum/sprite_accessory/X, mob/living/carbon/human/target, mob/user)
	if(X.name == DEVELOPER_WARNING_NAME)
		return FALSE
	if(!isnull(X.species_allowed) && !(target.species.name in X.species_allowed) && (!istype(target.species, /datum/species/custom))) // Letting custom species access wings/ears/tails.
		return FALSE
	if(!X.can_be_selected && (!user || !check_rights_for(user.client, R_HOLDER))) //So staff can quickly change people's appearance for events.
		return FALSE

	if(LAZYLEN(X.ckeys_allowed) && !(user?.ckey in X.ckeys_allowed) && !(target.ckey in X.ckeys_allowed))
		return FALSE

	return TRUE

// Subtypes for specific items or machines:
// *******************************************************
// Salon Pro
// *******************************************************
/datum/tgui_module/appearance_changer/mirror
	name = "SalonPro Nano-Mirror&trade;"
	flags = APPEARANCE_ALL_HAIR
	customize_usr = TRUE

/datum/tgui_module/appearance_changer/mirror/coskit
	name = "SalonPro Porta-Makeover Deluxe&trade;"

// *******************************************************
// Vore TF
// *******************************************************
/datum/tgui_module/appearance_changer/vore
	name = "Appearance Editor (Vore)"
	flags = APPEARANCE_ALL

DECLARE_UI_STATE(/datum/tgui_module/appearance_changer/vore, GLOB.tgui_conscious_state)

/datum/tgui_module/appearance_changer/vore/tgui_status(mob/user, datum/tgui_state/state)
	if(!isbelly(owner().loc))
		return STATUS_CLOSE
	return ..()

/datum/tgui_module/appearance_changer/vore/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		qdel(src)

/datum/tgui_module/appearance_changer/vore/update_active_camera_screen(datum/source, datum/om/event/movable_attempted_move/event)
	cam_screen.vis_contents = list(owner())
	cam_background.icon_state = "clear"
	cam_background.fill_rect(1, 1, 1, 1)
	local_skybox.cut_overlays()

/datum/tgui_module/appearance_changer/vore/changed_hook(flag, mob/user)
	var/mob/living/carbon/human/M = owner()
	var/mob/living/O = user

	switch(flag)
		if(APPEARANCECHANGER_CHANGED_RACE)
			to_chat(M, span_notice("You lose sensation of your body, feeling only the warmth of everything around you... "))
			to_chat(O, span_notice("Your body shifts as you make dramatic changes to your captive's body."))
		if(APPEARANCECHANGER_CHANGED_GENDER)
			to_chat(M, span_notice("Your body feels very strange..."))
			to_chat(O, span_notice("You feel strange as you alter your captive's gender."))
		if(APPEARANCECHANGER_CHANGED_GENDER_ID)
			to_chat(M, span_notice("You start to feel... [capitalize(M.gender)]?"))
			to_chat(O, span_notice("You feel strange as you alter your captive's gender identity."))
		if(APPEARANCECHANGER_CHANGED_SKINTONE, APPEARANCECHANGER_CHANGED_SKINCOLOR)
			to_chat(M, span_notice("Your body tingles all over..."))
			to_chat(O, span_notice("You tingle as you make noticeable changes to your captive's body."))
		if(APPEARANCECHANGER_CHANGED_HAIRSTYLE, APPEARANCECHANGER_CHANGED_HAIRCOLOR, APPEARANCECHANGER_CHANGED_F_HAIRSTYLE, APPEARANCECHANGER_CHANGED_F_HAIRCOLOR)
			to_chat(M, span_notice("Your body tingles all over..."))
			to_chat(O, span_notice("You tingle as you make noticeable changes to your captive's body."))
		if(APPEARANCECHANGER_CHANGED_EYES)
			to_chat(M, span_notice("You feel lightheaded and drowsy..."))
			to_chat(O, span_notice("You feel warm as you make subtle changes to your captive's body."))

// *******************************************************
// Weaver Cocoon
// *******************************************************
/datum/tgui_module/appearance_changer/cocoon
	name ="Appearance Editor (Cocoon)"
	flags = APPEARANCE_ALL_COSMETIC
	customize_usr = TRUE

/datum/tgui_module/appearance_changer/cocoon/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		qdel(src)

/datum/tgui_module/appearance_changer/cocoon/tgui_status(mob/user, datum/tgui_state/state)
	if(!istype(owner().loc, /obj/item/holder/micro))
		return STATUS_CLOSE
	return ..()

// *******************************************************
// Morph Superpower
// *******************************************************
/datum/tgui_module/appearance_changer/superpower
	name ="Appearance Editor (Superpower)"
	flags = APPEARANCE_ALL_COSMETIC
	customize_usr = TRUE

/datum/tgui_module/appearance_changer/superpower/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		qdel(src)

/datum/tgui_module/appearance_changer/superpower/tgui_status(mob/user, datum/tgui_state/state)
	var/datum/gene/G = get_gene_from_trait(/datum/trait/positive/superpower_morph)
	if(!owner().dna.GetSEState(G.block))
		return STATUS_CLOSE
	return ..()

// *******************************************************
// Innate Species Transformation.
// *******************************************************
/datum/tgui_module/appearance_changer/innate
	name ="Appearance Editor (Innate)"
	flags = APPEARANCE_ALL_COSMETIC
	customize_usr = TRUE

/datum/tgui_module/appearance_changer/innate/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		qdel(src)

/datum/tgui_module/appearance_changer/innate/tgui_status(mob/user, datum/tgui_state/state)
	if(owner().stat != CONSCIOUS)
		return STATUS_CLOSE
	return ..()

// *******************************************************
// Body design console
// *******************************************************
/datum/tgui_module/appearance_changer/body_designer
	name ="Appearance Editor (Body Designer)"
	flags = APPEARANCE_ALL
	/// The design console that owns us (a relation view)
	var/obj/machinery/computer/transhuman/designer/linked_body_design_console = null

/datum/tgui_module/appearance_changer/body_designer/tgui_status(mob/user, datum/tgui_state/state)
	if(!istype(host(),/obj/machinery/computer/transhuman/designer))
		return STATUS_CLOSE
	return ..()

// its design console drops the record (we leave its designer_gui in phase 2).
/datum/tgui_module/appearance_changer/body_designer/on_destroy(force)
	var/obj/machinery/computer/transhuman/designer/DC = linked_body_design_console
	if(DC)
		DC.selected_record = FALSE
	..()

/datum/tgui_module/appearance_changer/body_designer/proc/make_fake_owner()
	// checks for monkey to tell if on the menu
	if(owner())
		om_unhook(owner(), /datum/om/event/movable_attempted_move, src)
		own_clear(src, nameof(mannequin), OWN_DELETE)
		rel_clear(src, nameof(owner))
	rel_set(src, nameof(mannequin), new /mob/living/carbon/human(src))
	rel_set(src, nameof(owner), mannequin)
	owner().set_species(SPECIES_LLEILL)
	owner().species.produceCopy(owner().species.traits.Copy(),owner(),null,FALSE)
	owner().invisibility = INVISIBILITY_ABSTRACT
	// Add listeners back
	dq_add_recursive_move(owner())
	om_hook(owner(), /datum/om/event/movable_attempted_move, src, PROC_REF(update_active_camera_screen))

/datum/tgui_module/appearance_changer/body_designer/proc/load_record_to_body(datum/transhuman/body_record/current_project)
	if(owner())
		om_unhook(owner(), /datum/om/event/movable_attempted_move, src)
		own_clear(src, nameof(mannequin), OWN_DELETE)
		rel_clear(src, nameof(owner))
	rel_set(src, nameof(mannequin), current_project.produce_human_mob(src,FALSE,FALSE,"Designer [rand(999)]"))
	rel_set(src, nameof(owner), mannequin)
	// Update some specifics from the current record
	owner().dna.blood_reagents = current_project.mydna.dna.blood_reagents
	owner().dna.blood_color = current_project.mydna.dna.blood_color
	owner().resize(current_project.sizemult, FALSE)
	owner().appearance_flags = current_project.aflags
	owner().weight = current_project.weight
	if(current_project.speciesname)
		owner().custom_species = current_project.speciesname
	// Add listeners back
	dq_add_recursive_move(owner())
	om_hook(owner(), /datum/om/event/movable_attempted_move, src, PROC_REF(update_active_camera_screen))

/datum/tgui_module/appearance_changer/self_deleting
/datum/tgui_module/appearance_changer/self_deleting/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		qdel(src)

/// The last_camera_turf this refers to (a relation view: null once that is deleted).
/datum/tgui_module/appearance_changer/proc/last_camera_turf() as /turf
	return last_camera_turf

/// The owner this refers to (a relation view: null once that is deleted).
/datum/tgui_module/appearance_changer/proc/owner() as /mob/living/carbon/human
	return owner

/// A colour the appearance changer asks for; `field` is the tgui action it answers. Re-checked
/// on the answer: the user can still work the changer.
/datum/om/prompt/color/appearance
	ui_refresh_if_true = TRUE
	var/field
	var/datum/tgui_state/ui_state
	/// ears_secondary_color: the colour channel.
	var/channel
	/// marking: the marking's name.
	var/marking_name

/// The changer's windows refresh when the answer proc reports a change.
/datum/om/prompt/color/appearance/prepare()
	. = ..()
	rel_set(src, nameof(ui_refresh), subject)

/datum/om/prompt/color/appearance/valid()
	var/datum/tgui_module/appearance_changer/changer = subject
	if(!picked_color || !changer.owner())
		return "no change"
	return changer.can_still_topic(answerer, ui_state) ? null : "not usable"

/// Asks `user` for one of the changer's colours; the answer lands in appearance_color_picked().
/datum/tgui_module/appearance_changer/proc/ask_color(mob/user, datum/tgui_state/state, field, title, message, default, channel, marking_name)
	om_ask(user, /datum/om/prompt/color/appearance, PROC_REF(appearance_color_picked), subject = src, ui_state = state, field = field, title = title, message = message, default = default, channel = channel, marking_name = marking_name)

/// TRUE when the colour changed something (the prompt then refreshes the changer's windows).
/datum/tgui_module/appearance_changer/proc/appearance_color_picked(datum/om/prompt/color/appearance/ask)
	var/channel = ask.channel
	var/name_marking = ask.marking_name
	switch(ask.field)
		if("skin_color")
			var/r_skin = hex2num(copytext(ask.picked_color, 2, 4))
			var/g_skin = hex2num(copytext(ask.picked_color, 4, 6))
			var/b_skin = hex2num(copytext(ask.picked_color, 6, 8))
			if(owner().change_skin_color(r_skin, g_skin, b_skin))
				update_dna(owner())
				changed_hook(APPEARANCECHANGER_CHANGED_SKINCOLOR, ask.answerer)
				return TRUE
		if("hair_color")
			var/r_hair = hex2num(copytext(ask.picked_color, 2, 4))
			var/g_hair = hex2num(copytext(ask.picked_color, 4, 6))
			var/b_hair = hex2num(copytext(ask.picked_color, 6, 8))
			if(owner().change_hair_color(r_hair, g_hair, b_hair))
				update_dna(owner())
				changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
				return TRUE
		if("hair_color_grad")
			var/r_grad = hex2num(copytext(ask.picked_color, 2, 4))
			var/g_grad = hex2num(copytext(ask.picked_color, 4, 6))
			var/b_grad = hex2num(copytext(ask.picked_color, 6, 8))
			if(owner().change_grad_color(r_grad, g_grad, b_grad))
				update_dna(owner())
				changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
				return TRUE
		if("facial_hair_color")
			var/r_facial = hex2num(copytext(ask.picked_color, 2, 4))
			var/g_facial = hex2num(copytext(ask.picked_color, 4, 6))
			var/b_facial = hex2num(copytext(ask.picked_color, 6, 8))
			if(owner().change_facial_hair_color(r_facial, g_facial, b_facial))
				update_dna(owner())
				changed_hook(APPEARANCECHANGER_CHANGED_F_HAIRCOLOR, ask.answerer)
				return TRUE
		if("eye_color")
			var/r_eyes = hex2num(copytext(ask.picked_color, 2, 4))
			var/g_eyes = hex2num(copytext(ask.picked_color, 4, 6))
			var/b_eyes = hex2num(copytext(ask.picked_color, 6, 8))
			if(owner().change_eye_color(r_eyes, g_eyes, b_eyes))
				update_dna(owner())
				changed_hook(APPEARANCECHANGER_CHANGED_EYES, ask.answerer)
				return TRUE
		if("ears_color")
			owner().r_ears = hex2num(copytext(ask.picked_color, 2, 4))
			owner().g_ears = hex2num(copytext(ask.picked_color, 4, 6))
			owner().b_ears = hex2num(copytext(ask.picked_color, 6, 8))
			update_dna(owner())
			owner().update_hair()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("ears2_color")
			owner().r_ears2 = hex2num(copytext(ask.picked_color, 2, 4))
			owner().g_ears2 = hex2num(copytext(ask.picked_color, 4, 6))
			owner().b_ears2 = hex2num(copytext(ask.picked_color, 6, 8))
			update_dna(owner())
			owner().update_hair()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("ears_secondary_color")
			if(channel > length(owner().ear_secondary_colors))
				return
			owner().ear_secondary_colors[channel] = ask.picked_color
			update_dna(owner())
			owner().update_hair()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("tail_color")
			owner().r_tail = hex2num(copytext(ask.picked_color, 2, 4))
			owner().g_tail = hex2num(copytext(ask.picked_color, 4, 6))
			owner().b_tail = hex2num(copytext(ask.picked_color, 6, 8))
			update_dna(owner())
			owner().update_tail_showing()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("tail2_color")
			owner().r_tail2 = hex2num(copytext(ask.picked_color, 2, 4))
			owner().g_tail2 = hex2num(copytext(ask.picked_color, 4, 6))
			owner().b_tail2 = hex2num(copytext(ask.picked_color, 6, 8))
			update_dna(owner())
			owner().update_tail_showing()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("tail3_color")
			owner().r_tail3 = hex2num(copytext(ask.picked_color, 2, 4))
			owner().g_tail3 = hex2num(copytext(ask.picked_color, 4, 6))
			owner().b_tail3 = hex2num(copytext(ask.picked_color, 6, 8))
			update_dna(owner())
			owner().update_tail_showing()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("wing_color")
			owner().r_wing = hex2num(copytext(ask.picked_color, 2, 4))
			owner().g_wing = hex2num(copytext(ask.picked_color, 4, 6))
			owner().b_wing = hex2num(copytext(ask.picked_color, 6, 8))
			update_dna(owner())
			owner().update_wing_showing()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("wing2_color")
			owner().r_wing2 = hex2num(copytext(ask.picked_color, 2, 4))
			owner().g_wing2 = hex2num(copytext(ask.picked_color, 4, 6))
			owner().b_wing2 = hex2num(copytext(ask.picked_color, 6, 8))
			update_dna(owner())
			owner().update_wing_showing()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("wing3_color")
			owner().r_wing3 = hex2num(copytext(ask.picked_color, 2, 4))
			owner().g_wing3 = hex2num(copytext(ask.picked_color, 4, 6))
			owner().b_wing3 = hex2num(copytext(ask.picked_color, 6, 8))
			update_dna(owner())
			owner().update_wing_showing()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("marking")
			var/datum/sprite_accessory/marking/mark_datum = GLOB.body_marking_styles_list[name_marking]
			if (owner().change_marking_color(mark_datum, ask.picked_color))
				return TRUE
		if("blood_color")
			if(can_change(owner(), APPEARANCE_MISC))
				owner().dna.blood_color = ask.picked_color
				changed_hook(APPEARANCECHANGER_CHANGED_RACE, ask.answerer)
				return TRUE
