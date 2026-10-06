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
	/// The flavor text a question is open for.
	var/pending_flavor_key

CAPABILITIES(/datum/tgui_module/appearance_changer)
	owns_one(nameof(cam_background), /atom/movable/screen/background)
	owns_one(nameof(cam_screen), /atom/movable/screen/map_view)
	owns_one(nameof(local_skybox), /atom/movable/screen/skybox)
	owns_one(nameof(mannequin), /mob/living/carbon/human)
	owns_many(nameof(cam_plane_masters))
	interface("AppearanceChanger")
	extend(TAG_UI, needs(req(PROC_REF(ui_cooled), because = MSG(appearance_changer/too_fast))))
	extend(TAG_UI, then(PROC_REF(ui_start_cooldown), early = TRUE))
	ref_one(nameof(owner), /mob/living/carbon/human)

	section(body, "The body buttons of the appearance changer: species, gender, skin, hair, eyes")
	op("race", ui_act("race", arg("race", schema_text(4096))), then(PROC_REF(ui_act_race)))
	op("gender", ui_act("gender", arg("gender")), then(PROC_REF(ui_act_gender)))
	op("gender_id", ui_act("gender_id", arg("gender_id", schema_text(4096))), then(PROC_REF(ui_act_gender_id)))
	op("skin_tone", ui_act("skin_tone"), needs(req(PROC_REF(can_tone), silent = TRUE)), asks(/datum/prompt/number, fields = list("title" = "Skin Tone", "question" = "Choose your character's skin-tone:\n(Light 1 - 220 Dark)", "default" = computed(PROC_REF(skin_tone_default)), "max_value" = 220, "min_value" = 1)), then(PROC_REF(ui_act_skin_tone)))
	op("skin_color", ui_act("skin_color"), then(PROC_REF(ui_act_skin_color)))
	op("hair", ui_act("hair", arg("name")), then(PROC_REF(ui_act_hair)))
	op("hair_grad", ui_act("hair_grad", arg("picked")), then(PROC_REF(ui_act_hair_grad)))
	op("hair_color", ui_act("hair_color"), then(PROC_REF(ui_act_hair_color)))
	op("hair_color_grad", ui_act("hair_color_grad"), then(PROC_REF(ui_act_hair_color_grad)))
	op("facial_hair", ui_act("facial_hair", arg("name")), then(PROC_REF(ui_act_facial_hair)))
	op("facial_hair_color", ui_act("facial_hair_color"), then(PROC_REF(ui_act_facial_hair_color)))
	op("eye_color", ui_act("eye_color"), then(PROC_REF(ui_act_eye_color)))

	section(parts, "The ears, tail, wings and markings of the appearance changer")
	op("ear", ui_act("ear", arg("clear"), arg("ref", schema_ref(/datum/sprite_accessory/ears))), then(PROC_REF(ui_act_ear)))
	op("ear_secondary", ui_act("ear_secondary", arg("clear"), arg("ref", schema_ref(/datum/sprite_accessory/ears))), then(PROC_REF(ui_act_ear_secondary)))
	op("ears_color", ui_act("ears_color"), then(PROC_REF(ui_act_ears_color)))
	op("ears2_color", ui_act("ears2_color"), then(PROC_REF(ui_act_ears2_color)))
	op("ears_alpha", ui_act("ears_alpha", arg("ears_alpha", num())), then(PROC_REF(ui_act_ears_alpha)))
	op("secondary_ears_alpha", ui_act("secondary_ears_alpha", arg("secondary_ears_alpha", num())), then(PROC_REF(ui_act_secondary_ears_alpha)))
	op("ears_secondary_color", ui_act("ears_secondary_color", arg("channel", num())), then(PROC_REF(ui_act_ears_secondary_color)))
	op("tail", ui_act("tail", arg("clear"), arg("ref", schema_ref(/datum/sprite_accessory/tail))), then(PROC_REF(ui_act_tail)))
	op("tail_color", ui_act("tail_color"), then(PROC_REF(ui_act_tail_color)))
	op("tail2_color", ui_act("tail2_color"), then(PROC_REF(ui_act_tail2_color)))
	op("tail3_color", ui_act("tail3_color"), then(PROC_REF(ui_act_tail3_color)))
	op("tail_alpha", ui_act("tail_alpha", arg("tail_alpha", num())), then(PROC_REF(ui_act_tail_alpha)))
	op("wing", ui_act("wing", arg("clear"), arg("ref", schema_ref(/datum/sprite_accessory/wing))), then(PROC_REF(ui_act_wing)))
	op("wing_color", ui_act("wing_color"), then(PROC_REF(ui_act_wing_color)))
	op("wing2_color", ui_act("wing2_color"), then(PROC_REF(ui_act_wing2_color)))
	op("wing3_color", ui_act("wing3_color"), then(PROC_REF(ui_act_wing3_color)))
	op("wing_alpha", ui_act("wing_alpha", arg("wing_alpha", num())), then(PROC_REF(ui_act_wing_alpha)))
	op("marking", ui_act("marking", arg("name", schema_text(4096)), arg("todo", num())), then(PROC_REF(ui_act_marking)))

	section(profile, "The view and the character profile of the appearance changer: names, base icon, blood, size, sounds, flavour text")
	op("rotate_view", ui_act("rotate_view"), then(PROC_REF(ui_act_rotate_view)))
	op("rename", ui_act("rename"), needs(req(PROC_REF(has_owner), silent = TRUE)), asks(/datum/prompt/text, fields = list("title" = "Sleeve Name", "question" = "Choose the a name:", "encode" = FALSE)), then(PROC_REF(ui_act_rename)))
	op("char_name", ui_act("char_name"), needs(req(PROC_REF(has_designer_console), silent = TRUE)), asks(/datum/prompt/text, fields = list("title" = "Name", "question" = "Input character's name:", "default" = computed(PROC_REF(char_name_default)), "max_len" = MAX_NAME_LEN, "name_text" = TRUE)), then(PROC_REF(ui_act_char_name)))
	op("race_name", ui_act("race_name"), then(PROC_REF(ui_act_race_name)))
	op("base_icon", ui_act("base_icon"), needs(req(PROC_REF(can_misc), silent = TRUE)), asks(/datum/prompt/choice, fields = list("title" = "Body Shape", "question" = "Please select basic shape.", "choices" = computed(PROC_REF(custom_species_bases)))), then(PROC_REF(ui_act_base_icon)))
	op("blood_reagent", ui_act("blood_reagent"), needs(req(PROC_REF(can_misc), silent = TRUE)), asks(/datum/prompt/choice, fields = list("title" = "Character Preference", "question" = "Please select blood restoration reagent:", "choices" = computed(PROC_REF(valid_blood_reagents)))), then(PROC_REF(ui_act_blood_reagent)))
	op("blood_color", ui_act("blood_color"), then(PROC_REF(ui_act_blood_color)))
	op("weight", ui_act("weight"), asks(/datum/prompt/number, fields = list("title" = "Character Preference", "question" = "Choose tbe character's relative body weight.\nThis measurement should be set relative to a normal 5'10'' person's body and not the actual size of the character.\n([WEIGHT_MIN]-[WEIGHT_MAX])", "max_value" = WEIGHT_MAX, "min_value" = WEIGHT_MIN, "step" = 0.01), step = "amount"), asks(/datum/prompt/choice, fields = list("title" = "Confirmation", "question" = "Is that number in pounds (lb) or kilograms (kg)?", "choices" = list("Pounds", "Kilograms")), step = "unit", when = PROC_REF(weight_given)), then(PROC_REF(ui_act_weight)))
	op("size_scale", ui_act("size_scale"), then(PROC_REF(ui_act_size_scale)))
	op("scale_appearance", ui_act("scale_appearance"), then(PROC_REF(ui_act_scale_appearance)))
	op("offset_override", ui_act("offset_override"), then(PROC_REF(ui_act_offset_override)))
	op("digitigrade", ui_act("digitigrade"), then(PROC_REF(ui_act_digitigrade)))
	op("species_sound", ui_act("species_sound"), then(PROC_REF(ui_act_species_sound)))
	op("flavor_text", ui_act("flavor_text", arg("target", schema_text(4096))), then(PROC_REF(ui_act_flavor_text)))

	section(records, "The save slots, body records and disks of the appearance changer")
	op("load_saveslot", ui_act("load_saveslot"), then(PROC_REF(ui_act_load_saveslot)))
	op("view_brec", ui_act("view_brec", arg("view_brec", schema_ref(/datum/transhuman/body_record))), then(PROC_REF(ui_act_view_brec)))
	op("view_stock_brec", ui_act("view_stock_brec", arg("view_stock_brec", schema_text(4096))), then(PROC_REF(ui_act_view_stock_brec)))
	op("loadfromdisk", ui_act("loadfromdisk"), then(PROC_REF(ui_act_loadfromdisk)))
	op("savetodisk", ui_act("savetodisk"), then(PROC_REF(ui_act_savetodisk)))
	op("ejectdisk", ui_act("ejectdisk"), then(PROC_REF(ui_act_ejectdisk)))
	op("back_to_library", ui_act("back_to_library"), then(PROC_REF(ui_act_back_to_library)))

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
		unobserve(owner(), /datum/notice/movable_attempted_move, src)
		PUBLISH_LEGACY(owner(), /datum/notice/human_dna_finalized)
		rel_clear(src, nameof(owner))
		rel_clear(src, nameof(last_camera_turf))
		cut_data()

/// Buttons are answered at most twice a second: spamming them is laggy.
/datum/tgui_module/appearance_changer/proc/ui_cooled(datum/act/op/A)
	return COOLDOWN_FINISHED(src, cooldown)

MSG_DEF_SELF(appearance_changer/too_fast, "You are changing appearance too fast!")

/datum/tgui_module/appearance_changer/proc/ui_start_cooldown(datum/act/op/A)
	COOLDOWN_START(src, cooldown, 0.5 SECONDS)
	return OP_OK

/datum/tgui_module/appearance_changer/proc/can_misc(datum/act/op/A)
	return can_change(owner(), APPEARANCE_MISC)

/datum/tgui_module/appearance_changer/proc/can_race(datum/act/op/A)
	return can_change(owner(), APPEARANCE_RACE)

/datum/tgui_module/appearance_changer/proc/has_owner(datum/act/op/A)
	return !!owner()

/datum/tgui_module/appearance_changer/proc/can_tone(datum/act/op/A)
	return can_change_skin_tone(owner())

/// The body designer's console, when the changer is the designer's.
/datum/tgui_module/appearance_changer/proc/designer_console()
	var/datum/tgui_module/appearance_changer/body_designer/BD = src
	return istype(BD) ? BD.linked_body_design_console : null

/datum/tgui_module/appearance_changer/proc/has_designer_console(datum/act/op/A)
	return !!designer_console()


/datum/tgui_module/appearance_changer/proc/ui_act_race(datum/act/op/A, race)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_RACE) && (race in valid_species))
		// A custom species is named before the change.
		if(race == "Custom Species")
			open_request(src, /datum/prompt/text, PROC_REF(custom_species_named), valid = PROC_REF(request_usable), answerer = user, question = "Input custom species name:", title = "Custom Species Name", max_len = MAX_NAME_LEN, name_text = TRUE, timeout = 0)
			return
		return change_race(user, race, null)
	return FALSE

/datum/tgui_module/appearance_changer/proc/custom_species_named(datum/act/request/A)
	if(!A.answer || isnull(A.answer.value))
		return
	if(!can_change(owner(), APPEARANCE_RACE) || !("Custom Species" in valid_species))
		return
	if(change_race(A.request.answerer, "Custom Species", A.answer.value))
		SStgui.update_uis(src)

/datum/tgui_module/appearance_changer/proc/change_race(mob/user, race, custom_name)
	if(owner().change_species(race))
		if(race == "Custom Species")
			owner().custom_species = custom_name
		cut_data()
		generate_data(user, owner())
		changed_hook(APPEARANCECHANGER_CHANGED_RACE, user)
		return 1
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_gender(datum/act/op/A, gender)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_GENDER) && (gender in get_genders(owner())))
		if(owner().change_gender(gender))
			cut_data()
			generate_data(user, owner())
			changed_hook(APPEARANCECHANGER_CHANGED_GENDER, user)
			return 1
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_gender_id(datum/act/op/A, gender_id)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_GENDER) && (gender_id in all_genders_define_list))
		owner().identifying_gender = gender_id
		changed_hook(APPEARANCECHANGER_CHANGED_GENDER_ID, user)
		return 1
	return FALSE

/datum/tgui_module/appearance_changer/proc/skin_tone_default(datum/act/op/A)
	return -owner().s_tone + 35

/datum/tgui_module/appearance_changer/proc/ui_act_skin_tone(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/prompt/P = A.answer
	var/new_s_tone = P?.value
	if(isnum(new_s_tone))
		new_s_tone = 35 - max(min( round(new_s_tone), 220),1)
		changed_hook(APPEARANCECHANGER_CHANGED_SKINTONE, user)
		return owner().change_skin_tone(new_s_tone)
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_skin_color(datum/act/op/A)
	var/mob/user = A.actor
	if(can_change_skin_color(owner()))
		ask_color(user, "skin_color", "Skin Color", "Choose your character's skin colour: ", rgb(owner().r_skin, owner().g_skin, owner().b_skin))
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_hair(datum/act/op/A, name)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_HAIR) && (name in valid_hairstyles))
		if(owner().change_hair(name))
			update_dna(owner())
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRSTYLE, user)
			return 1
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_hair_grad(datum/act/op/A, picked_arg)
	var/mob/user = A.actor
	var/picked = picked_arg
	if(picked && can_change(owner(), APPEARANCE_HAIR_COLOR))
		owner().grad_style = picked[1] // returned as a list
		update_dna(owner())
		owner().regenerate_icons()
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRSTYLE, user)
		return 1
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_hair_color(datum/act/op/A)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(user, "hair_color", "Hair Color", "Please select hair color.", rgb(owner().r_hair, owner().g_hair, owner().b_hair))
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_hair_color_grad(datum/act/op/A)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(user, "hair_color_grad", "Hair Color", "Please select hair gradiant color.", rgb(owner().r_grad, owner().g_grad, owner().b_grad))
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_facial_hair(datum/act/op/A, name)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_FACIAL_HAIR) && (name in valid_facial_hairstyles))
		if(owner().change_facial_hair(name))
			update_dna(owner())
			changed_hook(APPEARANCECHANGER_CHANGED_F_HAIRSTYLE, user)
			return 1
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_facial_hair_color(datum/act/op/A)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_FACIAL_HAIR_COLOR))
		ask_color(user, "facial_hair_color", "Facial Hair Color", "Please select facial hair color.", rgb(owner().r_facial, owner().g_facial, owner().b_facial))
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_eye_color(datum/act/op/A)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_EYE_COLOR))
		ask_color(user, "eye_color", "Eye Color", "Please select eye color.", rgb(owner().r_eyes, owner().g_eyes, owner().b_eyes))
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_ear(datum/act/op/A, clear, ref)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_ALL_HAIR))
		var/datum/sprite_accessory/ears/instance = ref
		if(clear)
			instance = null
		if(!istype(instance) && !clear)
			return FALSE
		owner().ear_style = instance
		owner().update_hair()
		update_dna(owner())
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRSTYLE, user)
		return TRUE
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_ear_secondary(datum/act/op/A, clear, ref)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_ALL_HAIR))
		var/datum/sprite_accessory/ears/instance = ref
		if(clear)
			instance = null
		if(!istype(instance) && !clear)
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

/datum/tgui_module/appearance_changer/proc/ui_act_ears_color(datum/act/op/A)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(user, "ears_color", "Ear Color", "Please select ear color.", rgb(owner().r_ears, owner().g_ears, owner().b_ears))
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_ears2_color(datum/act/op/A)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(user, "ears2_color", "2nd Ear Color", "Please select secondary ear color.", rgb(owner().r_ears2, owner().g_ears2, owner().b_ears2))
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_ears_alpha(datum/act/op/A, ears_alpha)
	var/mob/user = A.actor
	var/new_alpha = clamp(ears_alpha, 0, 255)
	if(isnum(new_alpha))
		owner().a_ears = new_alpha
		update_dna(owner())
		owner().update_hair()
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, user)
		return 1
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_secondary_ears_alpha(datum/act/op/A, secondary_ears_alpha)
	var/mob/user = A.actor
	var/new_alpha = clamp(secondary_ears_alpha, 0, 255)
	if(isnum(new_alpha))
		owner().a_ears2 = new_alpha
		update_dna(owner())
		owner().update_hair()
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, user)
		return 1
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_ears_secondary_color(datum/act/op/A, channel_arg)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		var/channel = channel_arg
		if(channel > length(owner().ear_secondary_colors))
			return TRUE
		var/existing = LAZYACCESS(owner().ear_secondary_colors, channel) || "#ffffff"
		ask_color(user, "ears_secondary_color", "2nd Ear Color", "Please select ear color.", existing, channel = channel)
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_tail(datum/act/op/A, clear, ref)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_ALL_HAIR))
		var/datum/sprite_accessory/tail/instance = ref
		if(clear)
			instance = null
		if(!istype(instance) && !clear)
			return FALSE
		owner().tail_style = instance
		owner().update_tail_showing()
		update_dna(owner())
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRSTYLE, user)
		return TRUE
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_tail_color(datum/act/op/A)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(user, "tail_color", "Tail Color", "Please select tail color.", rgb(owner().r_tail, owner().g_tail, owner().b_tail))
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_tail2_color(datum/act/op/A)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(user, "tail2_color", "2nd Tail Color", "Please select secondary tail color.", rgb(owner().r_tail2, owner().g_tail2, owner().b_tail2))
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_tail3_color(datum/act/op/A)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(user, "tail3_color", "3rd Tail Color", "Please select tertiary tail color.", rgb(owner().r_tail3, owner().g_tail3, owner().b_tail3))
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_tail_alpha(datum/act/op/A, tail_alpha)
	var/mob/user = A.actor
	var/new_alpha = clamp(tail_alpha, 0, 255)
	if(isnum(new_alpha))
		owner().a_tail = new_alpha
		update_dna(owner())
		owner().update_tail_showing()
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, user)
		return 1
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_wing(datum/act/op/A, clear, ref)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_ALL_HAIR))
		var/datum/sprite_accessory/wing/instance = ref
		if(clear)
			instance = null
		if(!istype(instance) && !clear)
			return FALSE
		owner().wing_style = instance
		owner().update_wing_showing()
		update_dna(owner())
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRSTYLE, user)
		return TRUE
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_wing_color(datum/act/op/A)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(user, "wing_color", "Wing Color", "Please select wing color.", rgb(owner().r_wing, owner().g_wing, owner().b_wing))
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_wing2_color(datum/act/op/A)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(user, "wing2_color", "2nd Wing Color", "Please select secondary wing color.", rgb(owner().r_wing2, owner().g_wing2, owner().b_wing2))
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_wing3_color(datum/act/op/A)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_HAIR_COLOR))
		ask_color(user, "wing3_color", "3rd Wing Color", "Please select tertiary wing color.", rgb(owner().r_wing3, owner().g_wing3, owner().b_wing3))
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_wing_alpha(datum/act/op/A, wing_alpha)
	var/mob/user = A.actor
	var/new_alpha = clamp(wing_alpha, 0, 255)
	if(isnum(new_alpha))
		owner().a_wing = new_alpha
		update_dna(owner())
		owner().update_wing_showing()
		changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, user)
		return 1
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_marking(datum/act/op/A, name, todo_arg)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_ALL_HAIR))
		var/todo = todo_arg
		var/name_marking = name
		switch (todo)
			if (0) //delete
				if (name_marking)
					var/datum/sprite_accessory/marking/mark_datum = GLOB.body_marking_styles_list[name_marking]
					if (owner().remove_marking(mark_datum))
						changed_hook(APPEARANCECHANGER_CHANGED_HAIRSTYLE, user)
						return TRUE
			if (1) //add
				if(name_marking)
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
				ask_color(user, "marking", "Marking color", "Please select marking color", current, marking_name = name_marking)
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_rotate_view(datum/act/op/A)
	owner().set_dir(turn(owner().dir, 90))
	return TRUE

/datum/tgui_module/appearance_changer/proc/ui_act_rename(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/prompt/P = A.answer
	var/raw_name = P?.value
	if(owner() && !isnull(raw_name) && can_change(owner(), APPEARANCE_RACE))
		var/new_name = sanitize_name(raw_name, owner().species, FALSE) // can't edit synths
		if(new_name)
			owner().dna.real_name = new_name
			owner().real_name = new_name
			owner().name = new_name
			return TRUE
		else
			to_chat(user, span_warning("Invalid name. Your name should be at least 2 and at most [MAX_NAME_LEN] characters long. It may only contain the characters A-Z, a-z, -, ' and ."))
			return TRUE
	return FALSE

/datum/tgui_module/appearance_changer/proc/char_name_default(datum/act/op/A)
	return owner().name

/datum/tgui_module/appearance_changer/proc/ui_act_char_name(datum/act/op/A)
	var/datum/prompt/P = A.answer
	var/new_name = P?.value
	if(designer_console() && !isnull(new_name) && can_change(owner(), APPEARANCE_RACE)) // new name can be empty, it uses base species if so
		owner().name = new_name
		owner().real_name = owner().name
		owner().dna.real_name = owner().name
		return TRUE
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_race_name(datum/act/op/A)
	open_request(src, /datum/prompt/text, PROC_REF(race_name_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "Input custom species name:", title = "Custom Species Name", default = owner().custom_species, max_len = MAX_NAME_LEN, name_text = TRUE, timeout = 0)

/datum/tgui_module/appearance_changer/proc/race_name_answered(datum/act/request/A)
	race_name_answered_apply(A)
	SStgui.update_uis(src)

/datum/tgui_module/appearance_changer/proc/race_name_answered_apply(datum/act/request/A)
	if(!A.answer)
		return
	var/new_name = A.answer.value
	if(can_change(owner(), APPEARANCE_RACE)) // new name can be empty, it uses base species if so
		owner().custom_species = new_name
		return TRUE
	return FALSE

/datum/tgui_module/appearance_changer/proc/custom_species_bases(datum/act/op/A)
	return GLOB.custom_species_bases

/datum/tgui_module/appearance_changer/proc/ui_act_base_icon(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/prompt/P = A.answer
	var/new_species = P?.value
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
		generate_data(user, owner())
		changed_hook(APPEARANCECHANGER_CHANGED_RACE, user)
		return TRUE
	return FALSE

/datum/tgui_module/appearance_changer/proc/valid_blood_reagents(datum/act/op/A)
	return GLOB.valid_bloodreagents

/datum/tgui_module/appearance_changer/proc/ui_act_blood_reagent(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/prompt/P = A.answer
	var/new_blood_reagents = P?.value
	if(new_blood_reagents)
		owner().dna.blood_reagents = new_blood_reagents
		changed_hook(APPEARANCECHANGER_CHANGED_RACE, user)
		return TRUE
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_blood_color(datum/act/op/A)
	var/mob/user = A.actor
	var/current = owner().species.blood_color ? owner().species.blood_color : "#A10808"
	ask_color(user, "blood_color", "Blood color", "Please select blood color", current)
	return FALSE

/// The unit is asked once a weight was given and may be set.
/datum/tgui_module/appearance_changer/proc/weight_given(datum/act/op/A)
	var/datum/prompt/P = A.step_answer("amount")
	return P?.value && can_change(owner(), APPEARANCE_MISC)

/datum/tgui_module/appearance_changer/proc/ui_act_weight(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/prompt/amount_answer = A.step_answer("amount")
	var/datum/prompt/unit_answer = A.step_answer("unit")
	var/new_weight = amount_answer?.value
	var/unit_of_measurement = unit_answer?.value
	if(new_weight && can_change(owner(), APPEARANCE_MISC) && unit_of_measurement)
		if(unit_of_measurement == "Pounds")
			new_weight = round(text2num(new_weight),4)
		if(unit_of_measurement == "Kilograms")
			new_weight = round(2.20462*text2num(new_weight),4)
		owner().weight = sanitize_integer(new_weight, WEIGHT_MIN, WEIGHT_MAX, owner().weight)
		changed_hook(APPEARANCECHANGER_CHANGED_RACE, user)
		return TRUE
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_size_scale(datum/act/op/A)
	open_request(src, /datum/prompt/number, PROC_REF(size_scale_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "Choose size, ranging from [RESIZE_MINIMUM * 100]% to [RESIZE_MAXIMUM * 100]%", title = "Set Size", max_value = RESIZE_MAXIMUM * 100, min_value = RESIZE_MINIMUM * 100, timeout = 0)

/datum/tgui_module/appearance_changer/proc/size_scale_answered(datum/act/request/A)
	size_scale_answered_apply(A)
	SStgui.update_uis(src)

/datum/tgui_module/appearance_changer/proc/size_scale_answered_apply(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/new_size = A.answer.value
	if(new_size && ISINRANGE(new_size,RESIZE_MINIMUM * 100,RESIZE_MAXIMUM * 100) && can_change(owner(), APPEARANCE_MISC))
		owner().resize(new_size / 100, animate = FALSE, ignore_prefs = TRUE)
		owner().regenerate_icons()
		owner().set_dir(owner().dir) // Causes a visual update for fuzzy/offset
		changed_hook(APPEARANCECHANGER_CHANGED_RACE, user)
		return TRUE
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_scale_appearance(datum/act/op/A)
	if(can_change(owner(), APPEARANCE_MISC))
		owner().dna.scale_appearance = !owner().dna.scale_appearance
		owner().fuzzy = owner().dna.scale_appearance
		owner().regenerate_icons()
		owner().set_dir(owner().dir) // Causes a visual update for fuzzy/offset
		return TRUE
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_offset_override(datum/act/op/A)
	if(can_change(owner(), APPEARANCE_MISC))
		owner().dna.offset_override = !owner().dna.offset_override
		owner().offset_override = owner().dna.offset_override
		owner().regenerate_icons()
		owner().set_dir(owner().dir) // Causes a visual update for fuzzy/offset
		return TRUE
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_digitigrade(datum/act/op/A)
	var/mob/user = A.actor
	if(can_change(owner(), APPEARANCE_MISC))
		owner().dna.digitigrade = !owner().dna.digitigrade
		owner().digitigrade = owner().dna.digitigrade
		owner().regenerate_icons()
		generate_data(user, owner())
		changed_hook(APPEARANCECHANGER_CHANGED_RACE, user)
		return TRUE
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_species_sound(datum/act/op/A)
	open_request(src, /datum/prompt/choice, PROC_REF(species_sound_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "Which set of sounds would you like to use? (Cough, Sneeze, Scream, Pain, Gasp, Death)", title = "Species Sounds", choices = GLOB.species_sound_map, timeout = 0)

/datum/tgui_module/appearance_changer/proc/species_sound_answered(datum/act/request/A)
	species_sound_answered_apply(A)
	SStgui.update_uis(src)

/datum/tgui_module/appearance_changer/proc/species_sound_answered_apply(datum/act/request/A)
	if(!A.answer)
		return
	var/choice = A.answer.value
	if(choice && can_change(owner(), APPEARANCE_MISC))
		var/datum/species/own_species = proto_private(owner(), nameof(/datum/dna::species)) // PROTO: private copy
		own_species.species_sounds = choice
		return TRUE
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_flavor_text(datum/act/op/A, target)
	var/mob/user = A.actor
	var/select_key = target
	if(select_key && can_change(owner(), APPEARANCE_MISC) && (select_key in owner().flavor_texts))
		pending_flavor_key = select_key
		var/question = "Set the flavor text for their [select_key]. Put in \"!clear\" to make blank."
		if(select_key == "general")
			question = "Give a general description of the character. This will be shown regardless of clothings. Put in \"!clear\" to make blank."
		open_request(src, /datum/prompt/text, PROC_REF(flavor_text_written), valid = PROC_REF(request_usable), answerer = user, question = question, title = "Flavor Text", default = html_decode(owner().flavor_texts[select_key]), multiline = TRUE, max_len = MAX_TGUI_INPUT, timeout = 0)
		return
	return FALSE

/datum/tgui_module/appearance_changer/proc/flavor_text_written(datum/act/request/A)
	flavor_text_written_apply(A)
	SStgui.update_uis(src)

/datum/tgui_module/appearance_changer/proc/flavor_text_written_apply(datum/act/request/A)
	var/select_key = pending_flavor_key
	if(!A.answer || isnull(A.answer.value) || !select_key || !can_change(owner(), APPEARANCE_MISC))
		return
	var/msg = strip_html_simple(A.answer.value)
	if(msg == "!clear") // allows empty to wipe flavor
		msg = ""
	var/mob/living/carbon/human/flavor_owner = owner()
	LAZYSET(flavor_owner.flavor_texts, select_key, msg)

/datum/tgui_module/appearance_changer/proc/ui_act_load_saveslot(datum/act/op/A)
	if(can_change(owner(), APPEARANCE_ALL_COSMETIC))
		open_request(src, /datum/prompt/yes_no, PROC_REF(saveslot_confirmed), valid = PROC_REF(request_usable), answerer = owner(), question = "Are you certain you wish to load the currently selected savefile?", title = "Load Savefile", timeout = 0)
	return

/datum/tgui_module/appearance_changer/proc/saveslot_confirmed(datum/act/request/A)
	if(!A.answer || !A.answer.value || !can_change(owner(), APPEARANCE_ALL_COSMETIC))
		return
	if(owner() && owner().client) //sanity
		owner().client.prefs.vanity_copy_to(owner(), FALSE, TRUE, FALSE, FALSE, FALSE)
	SStgui.update_uis(src)

/datum/tgui_module/appearance_changer/proc/ui_act_view_brec(datum/act/op/A, view_brec)
	var/mob/user = A.actor
	var/obj/machinery/computer/transhuman/designer/DC = null
	var/datum/tgui_module/appearance_changer/body_designer/BD = null
	if(istype(src,/datum/tgui_module/appearance_changer/body_designer))
		BD = src
		DC = BD.linked_body_design_console
	var/datum/transhuman/body_record/BR = view_brec
	if(BR && istype(BR.mydna))
		if(DC.allowed(user) || BR.ckey == user.ckey)
			BD.load_record_to_body(BR)
			owner().resleeve_lock = BR.locked
			owner().changeling_locked = BR.changeling_locked
			DC.selected_record = TRUE
	return TRUE

/datum/tgui_module/appearance_changer/proc/ui_act_view_stock_brec(datum/act/op/A, view_stock_brec)
	var/obj/machinery/computer/transhuman/designer/DC = null
	var/datum/tgui_module/appearance_changer/body_designer/BD = null
	if(istype(src,/datum/tgui_module/appearance_changer/body_designer))
		BD = src
		DC = BD.linked_body_design_console
	var/datum/species/S = GLOB.all_species[view_stock_brec]
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

/datum/tgui_module/appearance_changer/proc/ui_act_loadfromdisk(datum/act/op/A)
	var/mob/user = A.actor
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
		to_chat(user,span_notice("\The [owner()]'s bodyrecord was loaded from the disk."))
	return TRUE

/datum/tgui_module/appearance_changer/proc/ui_act_savetodisk(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/machinery/computer/transhuman/designer/DC = designer_console()
	if(!DC?.selected_record)
		return FALSE
	if(!DC.disk)
		return FALSE
	if(owner().changeling_locked)
		to_chat(user, span_warning("ERROR: Record too complex. Disk does not have enough space to store this record."))
	else if(owner().resleeve_lock)
		open_request(src, /datum/prompt/yes_no, PROC_REF(record_permission_answered), valid = PROC_REF(request_usable), answerer = user, question = "This body record will be written to a disk and allow any mind to inhabit it. This is against the current body owner's configured OOC preferences for body impersonation. Please confirm that you have permission to do this, and are sure! Admins will be notified.", title = "Mind Compatability", timeout = 0)
		return
	return write_record(user, DC)

/datum/tgui_module/appearance_changer/proc/record_permission_answered(datum/act/request/A)
	record_permission_answered_apply(A)
	SStgui.update_uis(src)

/datum/tgui_module/appearance_changer/proc/record_permission_answered_apply(datum/act/request/A)
	var/mob/user = A.request.answerer
	var/obj/machinery/computer/transhuman/designer/DC = designer_console()
	if(!A.answer || !DC?.selected_record || !DC.disk || !owner())
		return
	if(!A.answer.value)
		to_chat(user, span_warning("ERROR: This body record is restricted."))
	else
		message_admins("[user] wrote an unlocked version of [owner().real_name]'s bodyrecord to a disk. Their preferences do not allow body impersonation, but may be allowed with OOC consent.")
		owner().resleeve_lock = FALSE // unlock it, even though it's only temp, so you don't get the warning every time
	write_record(user, DC)

/datum/tgui_module/appearance_changer/proc/write_record(mob/user, obj/machinery/computer/transhuman/designer/DC)
	if(!owner().changeling_locked && (!owner().resleeve_lock && can_change(owner(), APPEARANCE_RACE)))
		// Create it from the mob
		to_chat(user,span_notice("\The [owner()]'s bodyrecord was saved to the disk."))
		owner().update_dna()
		var/datum/transhuman/body_record/record = new /datum/transhuman/body_record(owner(), FALSE, FALSE) // Saves a COPY! The old record is deleted
		record.locked = FALSE // remove lock
		rel_set(DC.disk, nameof(DC.disk.stored), record)
		DC.disk.name = "[initial(DC.disk.name)] ([owner().real_name])"
	return TRUE

/datum/tgui_module/appearance_changer/proc/ui_act_ejectdisk(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/machinery/computer/transhuman/designer/DC = null
	var/datum/tgui_module/appearance_changer/body_designer/BD = null
	if(istype(src,/datum/tgui_module/appearance_changer/body_designer))
		BD = src
		DC = BD.linked_body_design_console
	if(!DC.disk)
		return FALSE
	if(can_change(owner(), APPEARANCE_RACE))
		to_chat(user,span_notice("You eject the disk."))
		DC.disk.forceMove(get_turf(DC))
		own_take(DC, nameof(/obj/machinery/computer/scan_consolenew::disk))
		return TRUE
	return FALSE

/datum/tgui_module/appearance_changer/proc/ui_act_back_to_library(datum/act/op/A)
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
	observe(owner(), /datum/notice/movable_attempted_move, src, then(PROC_REF(update_active_camera_screen)))
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

/datum/tgui_module/appearance_changer/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
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

/datum/tgui_module/appearance_changer/proc/update_active_camera_screen(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
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

CAPABILITIES(/datum/tgui_module/appearance_changer/vore)
	interface("AppearanceChanger", state = nameof(GLOB.tgui_conscious_state))

/datum/tgui_module/appearance_changer/vore/tgui_status(mob/user, datum/tgui_state/state)
	if(!isbelly(owner().loc))
		return STATUS_CLOSE
	return ..()

/datum/tgui_module/appearance_changer/vore/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		spent(src, user)

/datum/tgui_module/appearance_changer/vore/update_active_camera_screen(datum/act/notice/N)
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
		spent(src, user)

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
		spent(src, user)

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
		spent(src, user)

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
		unobserve(owner(), /datum/notice/movable_attempted_move, src)
		own_clear(src, nameof(mannequin), OWN_DELETE)
		rel_clear(src, nameof(owner))
	rel_set(src, nameof(mannequin), new /mob/living/carbon/human(src))
	rel_set(src, nameof(owner), mannequin)
	owner().set_species(SPECIES_LLEILL)
	owner().species.produceCopy(owner().species.traits.Copy(),owner(),null,FALSE)
	owner().invisibility = INVISIBILITY_ABSTRACT
	// Add listeners back
	dq_add_recursive_move(owner())
	observe(owner(), /datum/notice/movable_attempted_move, src, then(PROC_REF(update_active_camera_screen)))

/datum/tgui_module/appearance_changer/body_designer/proc/load_record_to_body(datum/transhuman/body_record/current_project)
	if(owner())
		unobserve(owner(), /datum/notice/movable_attempted_move, src)
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
	observe(owner(), /datum/notice/movable_attempted_move, src, then(PROC_REF(update_active_camera_screen)))

/datum/tgui_module/appearance_changer/self_deleting
/datum/tgui_module/appearance_changer/self_deleting/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		spent(src, user)

/// The last_camera_turf this refers to (a relation view: null once that is deleted).
/datum/tgui_module/appearance_changer/proc/last_camera_turf() as /turf
	return last_camera_turf

/// The owner this refers to (a relation view: null once that is deleted).
/datum/tgui_module/appearance_changer/proc/owner() as /mob/living/carbon/human
	return owner

/// A colour the appearance changer asks for; `field` is the tgui action it answers.
/datum/prompt/color/appearance
	/// The tgui action the colour answers.
	var/field
	/// ears_secondary_color: the colour channel.
	var/channel
	/// marking: the marking's name.
	var/marking_name

/// Asks `user` for one of the changer's colours; the answer lands in appearance_color_picked().
/datum/tgui_module/appearance_changer/proc/ask_color(mob/user, field, title, message, default, channel, marking_name)
	open_request(src, /datum/prompt/color/appearance, PROC_REF(appearance_color_picked), valid = PROC_REF(request_usable), answerer = user, field = field, title = title, question = message, default = default, channel = channel, marking_name = marking_name, timeout = 0)

/// The colour changed something: the changer's windows refresh.
/datum/tgui_module/appearance_changer/proc/appearance_color_picked(datum/act/request/A)
	var/datum/prompt/color/appearance/ask = A.request
	if(!A.answer || !ask.value || !owner())
		return
	. = apply_color(ask)
	if(.)
		SStgui.update_uis(src)

/datum/tgui_module/appearance_changer/proc/apply_color(datum/prompt/color/appearance/ask)
	var/channel = ask.channel
	var/name_marking = ask.marking_name
	switch(ask.field)
		if("skin_color")
			var/r_skin = hex2num(copytext(ask.value, 2, 4))
			var/g_skin = hex2num(copytext(ask.value, 4, 6))
			var/b_skin = hex2num(copytext(ask.value, 6, 8))
			if(owner().change_skin_color(r_skin, g_skin, b_skin))
				update_dna(owner())
				changed_hook(APPEARANCECHANGER_CHANGED_SKINCOLOR, ask.answerer)
				return TRUE
		if("hair_color")
			var/r_hair = hex2num(copytext(ask.value, 2, 4))
			var/g_hair = hex2num(copytext(ask.value, 4, 6))
			var/b_hair = hex2num(copytext(ask.value, 6, 8))
			if(owner().change_hair_color(r_hair, g_hair, b_hair))
				update_dna(owner())
				changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
				return TRUE
		if("hair_color_grad")
			var/r_grad = hex2num(copytext(ask.value, 2, 4))
			var/g_grad = hex2num(copytext(ask.value, 4, 6))
			var/b_grad = hex2num(copytext(ask.value, 6, 8))
			if(owner().change_grad_color(r_grad, g_grad, b_grad))
				update_dna(owner())
				changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
				return TRUE
		if("facial_hair_color")
			var/r_facial = hex2num(copytext(ask.value, 2, 4))
			var/g_facial = hex2num(copytext(ask.value, 4, 6))
			var/b_facial = hex2num(copytext(ask.value, 6, 8))
			if(owner().change_facial_hair_color(r_facial, g_facial, b_facial))
				update_dna(owner())
				changed_hook(APPEARANCECHANGER_CHANGED_F_HAIRCOLOR, ask.answerer)
				return TRUE
		if("eye_color")
			var/r_eyes = hex2num(copytext(ask.value, 2, 4))
			var/g_eyes = hex2num(copytext(ask.value, 4, 6))
			var/b_eyes = hex2num(copytext(ask.value, 6, 8))
			if(owner().change_eye_color(r_eyes, g_eyes, b_eyes))
				update_dna(owner())
				changed_hook(APPEARANCECHANGER_CHANGED_EYES, ask.answerer)
				return TRUE
		if("ears_color")
			owner().r_ears = hex2num(copytext(ask.value, 2, 4))
			owner().g_ears = hex2num(copytext(ask.value, 4, 6))
			owner().b_ears = hex2num(copytext(ask.value, 6, 8))
			update_dna(owner())
			owner().update_hair()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("ears2_color")
			owner().r_ears2 = hex2num(copytext(ask.value, 2, 4))
			owner().g_ears2 = hex2num(copytext(ask.value, 4, 6))
			owner().b_ears2 = hex2num(copytext(ask.value, 6, 8))
			update_dna(owner())
			owner().update_hair()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("ears_secondary_color")
			if(channel > length(owner().ear_secondary_colors))
				return
			owner().ear_secondary_colors[channel] = ask.value
			update_dna(owner())
			owner().update_hair()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("tail_color")
			owner().r_tail = hex2num(copytext(ask.value, 2, 4))
			owner().g_tail = hex2num(copytext(ask.value, 4, 6))
			owner().b_tail = hex2num(copytext(ask.value, 6, 8))
			update_dna(owner())
			owner().update_tail_showing()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("tail2_color")
			owner().r_tail2 = hex2num(copytext(ask.value, 2, 4))
			owner().g_tail2 = hex2num(copytext(ask.value, 4, 6))
			owner().b_tail2 = hex2num(copytext(ask.value, 6, 8))
			update_dna(owner())
			owner().update_tail_showing()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("tail3_color")
			owner().r_tail3 = hex2num(copytext(ask.value, 2, 4))
			owner().g_tail3 = hex2num(copytext(ask.value, 4, 6))
			owner().b_tail3 = hex2num(copytext(ask.value, 6, 8))
			update_dna(owner())
			owner().update_tail_showing()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("wing_color")
			owner().r_wing = hex2num(copytext(ask.value, 2, 4))
			owner().g_wing = hex2num(copytext(ask.value, 4, 6))
			owner().b_wing = hex2num(copytext(ask.value, 6, 8))
			update_dna(owner())
			owner().update_wing_showing()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("wing2_color")
			owner().r_wing2 = hex2num(copytext(ask.value, 2, 4))
			owner().g_wing2 = hex2num(copytext(ask.value, 4, 6))
			owner().b_wing2 = hex2num(copytext(ask.value, 6, 8))
			update_dna(owner())
			owner().update_wing_showing()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("wing3_color")
			owner().r_wing3 = hex2num(copytext(ask.value, 2, 4))
			owner().g_wing3 = hex2num(copytext(ask.value, 4, 6))
			owner().b_wing3 = hex2num(copytext(ask.value, 6, 8))
			update_dna(owner())
			owner().update_wing_showing()
			changed_hook(APPEARANCECHANGER_CHANGED_HAIRCOLOR, ask.answerer)
			return TRUE
		if("marking")
			var/datum/sprite_accessory/marking/mark_datum = GLOB.body_marking_styles_list[name_marking]
			if (owner().change_marking_color(mark_datum, ask.value))
				return TRUE
		if("blood_color")
			if(can_change(owner(), APPEARANCE_MISC))
				owner().dna.blood_color = ask.value
				changed_hook(APPEARANCECHANGER_CHANGED_RACE, ask.answerer)
				return TRUE
