// The pet customize panel: the name, description, gender, colour and size settings of a simple mob (the Set Name, Set Description, Set Gender,
// Pick Color, Pick Size and Recolour verbs of its Settings group) in one TGUI window (console theme). The settings are the same procs of the mob
// as before; the panel's buttons call them, so what one asks, what it refuses and when it is used up is the proc's own business and is the same
// from the panel and from code. A setting is listed while the mob has been granted its proc.

#define PET_SET_NAME "set_name"
#define PET_SET_DESC "set_desc"
#define PET_SET_GENDER "choose_gender"
#define PET_SET_COLOR "pick_color"
#define PET_SET_SIZE "pick_size"
#define PET_SET_RECOLOUR "recolour"

/// Open panels: pet -> the panel's handle_of (a deleted panel stops resolving).
GLOBAL_ALIST_EMPTY(dq_pet_panels)

/datum/pet_panel
	var/mob/living/simple_mob/pet

/datum/pet_panel/New(mob/living/simple_mob/pet_mob)
	rel_set(src, nameof(pet), pet_mob)

/// Phase 2: leaves the per-pet panel index.
/datum/pet_panel/lifecycle_dematerialize()
	. = ..()
	if(pet)
		GLOB.dq_pet_panels -= handle_of(pet)

CAPABILITIES(/datum/pet_panel)
	ref_one(nameof(pet), /mob/living/simple_mob)
	interface("PetCustomize", title = "Customize", state = nameof(GLOB.tgui_always_state))
	op("pet_do", ui_act("pet_do", arg("action", schema_text(32))), then(PROC_REF(ui_act_pet_do)))

/datum/pet_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!pet || user != pet)
		return FALSE
	return TRUE

/// The settings of the panel, in order: id, label, the button's text, what it does and the proc of the mob that grants it.
GLOBAL_LIST_INIT(pet_panel_settings, list(
	list(PET_SET_NAME, "Name", "Rename", "Sets your mob's name. You only get to do this once.", /mob/living/simple_mob/proc/set_name),
	list(PET_SET_DESC, "Description", "Rewrite", "Set your description.", /mob/living/simple_mob/proc/set_desc),
	list(PET_SET_GENDER, "Gender", "Change", "Set your gender.", /mob/living/simple_mob/proc/choose_gender),
	list(PET_SET_COLOR, "Colour", "Pick", "You can set your colour! Only once.", /mob/living/simple_mob/proc/pick_color),
	list(PET_SET_SIZE, "Size", "Pick", "Pick a size. Only once.", /mob/living/simple_mob/proc/pick_size),
	list(PET_SET_RECOLOUR, "Recolour", "Recolour", "Repaint yourself with a colour matrix. Only once.", /mob/living/simple_mob/proc/ColorMate),
))

/// Why the setting cannot be used now, or null.
/datum/pet_panel/proc/setting_refusal(list/setting)
	switch(setting[1])
		if(PET_SET_NAME)
			if(pet.limit_renames && pet.nameset)
				return "You have already set your name. Ask an admin to reset it if you must."
		if(PET_SET_COLOR)
			if(pet.picked_color)
				return "You have already picked a colour. Ask an admin to reset it if you must."
		if(PET_SET_SIZE)
			if(pet.picked_size)
				return "You have already picked a size. Ask an admin to reset it if you must."
			if(!pet.vore_prefs?.resizable)
				return "You are immune to resizing."
		if(PET_SET_RECOLOUR)
			if(pet.has_recoloured)
				return "You have already recoloured yourself this round."
	return null

/// What the setting is now, as the window shows it.
/datum/pet_panel/proc/setting_value(id)
	switch(id)
		if(PET_SET_NAME)
			return "[pet.name]"
		if(PET_SET_DESC)
			return length(pet.desc) > 240 ? "[copytext(pet.desc, 1, 240)]..." : "[pet.desc]"
		if(PET_SET_GENDER)
			return "[pet.gender]"
		if(PET_SET_COLOR)
			return istext(pet.color) ? pet.color : "Natural"
		if(PET_SET_SIZE)
			return "[round(pet.size_multiplier * 100)]%"
		if(PET_SET_RECOLOUR)
			return pet.has_recoloured ? "Used" : "Available"
	return null

/// /datum/pet_panel's window data.
/datum/pet_panel/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["pet_name"] = pet ? "[pet.name]" : ""
	var/list/rows = list()
	if(pet)
		for(var/list/setting as anything in GLOB.pet_panel_settings)
			if(!pet.pet_setting_granted(setting))
				continue
			var/why = setting_refusal(setting)
			var/value = setting_value(setting[1])
			var/swatch = (setting[1] == PET_SET_COLOR && istext(pet.color)) ? pet.color : null
			rows += list(list("id" = setting[1], "label" = setting[2], "action" = setting[3], "desc" = setting[4], "value" = value, "swatch" = swatch, "enabled" = isnull(why), "why" = why))
	data["settings"] = rows
	return data

/datum/pet_panel/proc/ui_act_pet_do(datum/act/op/A, action)
	return run_action(A.actor, action)

/// Runs one setting for the pet that pressed it; FALSE when it is not this panel's pet, the setting is not granted or refused, or unknown.
/datum/pet_panel/proc/run_action(mob/user, action)
	if(!pet || user != pet)
		return FALSE
	for(var/list/setting as anything in GLOB.pet_panel_settings)
		if(setting[1] != action)
			continue
		if(!pet.pet_setting_granted(setting) || setting_refusal(setting))
			return FALSE
		call(pet, setting[5])()
		SStgui.update_uis(src)
		return TRUE
	return FALSE

/// Opens the customize window of this pet.
/mob/living/simple_mob/proc/open_pet_customize()
	var/key = handle_of(src)
	var/datum/pet_panel/panel = handle_get(ALAZYACCESS(GLOB.dq_pet_panels, key))
	if(!panel)
		panel = new(src)
		GLOB.dq_pet_panels[key] = handle_of(panel)
	panel.tgui_interact(src)

/// Has the pet been granted the proc of this setting (a row of GLOB.pet_panel_settings)?
/mob/living/simple_mob/proc/pet_setting_granted(list/setting)
	var/wanted = "[setting[5]]"
	for(var/granted_verb in verbs)
		if("[granted_verb]" == wanted)
			return TRUE
	return FALSE

/// Does this mob have any customize setting granted? (The Abilities panel lists the Customize command for those that do.)
/mob/living/proc/pet_customize_listed(id)
	return FALSE

/mob/living/simple_mob/pet_customize_listed(id)
	for(var/list/setting as anything in GLOB.pet_panel_settings)
		if(pet_setting_granted(setting))
			return TRUE
	return FALSE
