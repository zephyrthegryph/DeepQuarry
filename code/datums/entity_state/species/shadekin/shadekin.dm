//See comp_helpers.dm for helper procs.
/// Shadekin state (energy, phasing, powers). An owned plain datum held in
/// /mob/living/var/shadekin (one per mob); formerly a component. Add with add_shadekin().
/datum/shadekin
	VAR_PRIVATE/mob/living/owner

	//Energy Vars
	///How much energy we have RIGHT NOW
	var/dark_energy = 100
	///How much energy we can have
	var/max_dark_energy = 100
	///Always be at our max_dark_energy
	var/dark_energy_infinite = FALSE
	///How much energy we generate in the dark
	var/energy_dark = 0.75
	///How much energy we generate in the light
	var/energy_light = 0.25
	///If we care about eye color when it comes to factoring in energy
	var/eye_color_influences_energy = TRUE
	///Energy gain from nutrition
	var/nutrition_conversion_scaling = 0.5
	///If we convert nutrition to energy
	var/nutrition_energy_conversion = FALSE

	//Phase Vars
	///Are we currently in a phase transition?
	var/doing_phase = FALSE
	///Are we currently phased?
	var/in_phase = FALSE
	///If TRUE, voice is hidden when phased (shows as "Something")
	var/hide_voice_in_phase = TRUE
	///Chance to break lights on phase-in
	var/flicker_break_chance = 0
	///Color that lights will flicker to on phase-in. Off by default.
	var/flicker_color
	///Time that lights will flicker on phase-in. Default is 10 times.
	var/flicker_time = 10
	///Range that we flicker lights. Default is 10.
	var/flicker_distance = 10
	///If we can get the 'phase debuff' applied to us. (No using guns, dropping things in hands, etc).
	var/normal_phase = TRUE
	///If we drop items on phase.
	var/drop_items_on_phase = FALSE
	///If cameras count as watchers for us
	var/camera_counts_as_watcher = FALSE
	///Phase in animation
	var/phase_in_anim = /obj/effect/temp_visual/shadekin/phase_in
	///Phase out animation
	var/phase_out_anim = /obj/effect/temp_visual/shadekin/phase_out
	//How long does it take to complete
	var/phase_time = 0.5 SECONDS
	//Phase sound
	var/phase_noise = SFX_EFFECTS_STEALTHOFF

	//Dark Respite Vars (Unused on Virgo)
	///If we are in dark respite or not
	var/in_dark_respite = FALSE
	var/manual_respite = FALSE
	var/respite_activating = FALSE
	///If we return to The Dark upon death or not.
	var/no_retreat = FALSE

	//Dark Tunneling Vars (Unused on Virgo)
	///If we have already made a dark tunnel
	var/created_dark_tunnel = FALSE

	//Dark Maw Vars (Unused on Virgo)
	///Our current active dark maws: a relation list view (a maw that dies leaves it)
	var/list/obj/effect/abstract/dark_maw/active_dark_maws

	//Misc Vars
	///Eyecolor
	var/eye_color = BLUE_EYES
	///For downstream. Enables some extra verbs. Causes things to drop in hand when you phase.
	var/extended_kin = FALSE

/datum/shadekin/full
	extended_kin = TRUE
	drop_items_on_phase = TRUE
	camera_counts_as_watcher = TRUE

/datum/shadekin/full/rakshasa
	flicker_time = 0 //Rakshasa don't flicker lights when they phase in.
	dark_energy_infinite = TRUE
	normal_phase = FALSE

/datum/shadekin/New(mob/living/new_owner, manual = FALSE)
	..()
	if(!isliving(new_owner) || issilicon(new_owner))
		log_runtime("SHADEKIN: [type] created for incompatible [new_owner] ([new_owner?.type]); ignoring.")
		return
	rel_set(src, nameof(owner), new_owner) // one-sided back view: the mob owns us in its shadekin var
	rel_set(owner, nameof(owner.shadekin), src)
	if(!ishuman(owner))
		om_stage_add(owner, /datum/om/stage/life/trait/shadekin) //Happens every life tick (mobs)
	//Humans are ticked by the species_components life stage instead.

	// Voice/name hooks
	observe(owner, /datum/act/name_voice, src, instead(then(PROC_REF(on_get_voice))))
	observe(owner, /datum/act/name_alt, src, instead(then(PROC_REF(on_get_alt_name))))
	observe(owner, /datum/act/name_visible, src, instead(then(PROC_REF(on_get_visible_name))))

	// This datum is the source for every ability it grants
	// (code/datums/abilities/ability.dm); revoked with it in
	// lifecycle_prerelease() below, whatever kind of shadekin this is.
	for(var/ability_id in granted_ability_ids())
		owner.grant_ability(ability_id, src)

	handle_comp() //First hit is free!

	//decides what 'eye color' we are and how much energy we should get
	set_shadekin_eyecolor() //Gets what eye color we are.
	set_eye_energy() //Sets the energy values based on our eye color.

	//Misc stuff we need to do
	grant(owner, granted_verb(/mob/living/proc/shadekin_control_panel), src)

	if(manual)
		lateload_pref_data()

/mob/living/var/datum/shadekin/shadekin

/// Gives this mob shadekin state of `path` (or returns the existing one, like LoadComponent did).
/mob/living/proc/add_shadekin(path = /datum/shadekin, manual = FALSE)
	RETURN_TYPE(/datum/shadekin)
	if(shadekin)
		return shadekin
	var/datum/shadekin/SK = new path(src, manual)
	if(shadekin != SK) //incompatible mob
		qdel(SK)
		return null
	return SK

/// Removes this mob's shadekin state, if any.
/mob/living/proc/remove_shadekin()
	own_clear(src, nameof(shadekin), OWN_DELETE)

// revokes its granted abilities, trait stage and verbs; hides the owner's energy hud.
/datum/shadekin/lifecycle_prerelease()
	..()
	if(!owner)
		return
	for(var/ability_id in granted_ability_ids())
		owner.revoke_ability(ability_id, src)
	if(!ishuman(owner))
		om_stage_remove(owner, /datum/om/stage/life/trait/shadekin)
	revoke(owner, granted_verb(/mob/living/proc/shadekin_control_panel), src)
	if(!QDELING(owner) && owner.shadekin_display)
		owner.shadekin_display.invisibility = INVISIBILITY_ABSTRACT

/datum/shadekin/proc/recalc_values()
	set_shadekin_eyecolor() //Gets what eye color we are.
	set_eye_energy() //Sets the energy values based on our eye color.

///Handles the shadekin ticking (species_components stage for humans, trait stage for mobs).
/datum/shadekin/proc/handle_comp()
	if(QDELETED(owner))
		return
	if(owner.stat == DEAD) //dead, don't process.
		return
	handle_shade()

///Handles the shadekin's energy gain and loss.
/datum/shadekin/proc/handle_shade()
	//Shifted kin don't gain/lose energy (and save time if we're at the cap)
	var/darkness = 1
	var/dark_gains = 0

	var/suit = owner.get_equipped_item(SLOT_ID_SUIT)
	if(istype(suit, /obj/item/clothing/suit/space/rig))
		if(dark_energy)
			to_chat(owner, span_warning("You feel your energy waning and your powers being blocked from the heavy equipment you're wearing!"))
		dark_energy = 0
		return

	var/turf/T = get_turf(owner)
	if(!T)
		dark_gains = 0
		return

	var/brightness = T.get_lumcount() //Brightness in 0.0 to 1.0
	darkness = 1-brightness //Invert
	var/is_dark = (darkness >= 0.5)

	if(in_phase)
		dark_gains = 0
	else
		//Heal (very) slowly in good darkness
		if(is_dark)
		//The below sends a DB query...This needs to be fixed before this can be enabled as we're now dealing with signal handlers.
		//Reenable once that mess is taken care of.
			owner.mend(TREAT_BURN_CARE, 0.10 * darkness)
			owner.mend(TREAT_TISSUE_REPAIR, 0.10 * darkness)
			owner.mend(TREAT_ANTITOXIN, 0.10 * darkness)
			//energy_dark and energy_light are set by the shadekin eye traits.
			//These are balanced around their playstyles and 2 planned new aggressive abilities
			dark_gains = energy_dark
		else
			dark_gains = energy_light

	dark_gains = handle_nutrition_conversion(dark_gains)

	shadekin_adjust_energy(dark_gains)

	//Update huds
	update_shadekin_hud()

/datum/shadekin/proc/calculate_stun()
	var/stun_time = 3
	if(flicker_time > 0)
		stun_time -= min(flicker_time / 5, 1)
	if(flicker_distance > 0)
		stun_time -= min(flicker_distance / 5, 1)
	if(flicker_break_chance > 0)
		stun_time -= min(flicker_break_chance / 5, 1)
	return stun_time

///Sees if the savefile we have selected in CHARACTER SETUP is the same as our ACTIVE CHARACTER savefile.
/datum/shadekin/proc/correct_savefile_selected()
	if(owner.client.prefs.default_slot == owner.mind.loaded_from_slot)
		return TRUE
	return FALSE

DECLARE_UI(/datum/shadekin, "ShadekinConfig", UI_TITLE("Shadekin Config"))

UI_DATA_REPLACE(/datum/shadekin, "merge:ui_data_datum_shadekin{stun_time:unknown,flicker_time:num,flicker_color:unknown,flicker_break_chance:num,flicker_distance:num,no_retreat:num,nutrition_energy_conversion:num,hide_voice_in_phase:num,extended_kin:num,savefile_selected:unknown}")

/// The computed part of /datum/shadekin's window data (declared on its UI_DATA row).
/datum/shadekin/proc/ui_data_datum_shadekin(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/data = list(
		"stun_time" = calculate_stun(),
		"flicker_time" = flicker_time,
		"flicker_color" = flicker_color,
		"flicker_break_chance" = flicker_break_chance,
		"flicker_distance" = flicker_distance,
		"no_retreat" = no_retreat,
		"nutrition_energy_conversion" = nutrition_energy_conversion,
		"hide_voice_in_phase" = hide_voice_in_phase,
		"extended_kin" = extended_kin,
		"savefile_selected" = correct_savefile_selected()
	)

	return data

/datum/shadekin/tgui_close(mob/user)
	SScharacter_setup.queue_preferences_save(user?.client?.prefs)
	. = ..()

/datum/shadekin/proc/flicker_color_picked(datum/om/prompt/color/ask)
	if(!ask.picked_color)
		return
	flicker_color = ask.picked_color
	ask.answerer.write_preference_directly(/datum/preference/color/living/flicker_color, ask.picked_color, WRITE_PREF_MANUAL, save_to_played_slot = TRUE)

UI_ACT(/datum/shadekin, "adjust_time", ui_act_adjust_time, UI_ARG_NUM("val"))
UI_ACT_PROC(/datum/shadekin, ui_act_adjust_time)
	var/new_time = params["val"]
	new_time = CLAMP(new_time, 2, 20)
	if(!isnum(new_time))
		return FALSE
	flicker_time = new_time
	ui.user.write_preference_directly(/datum/preference/numeric/living/flicker_time, new_time, WRITE_PREF_MANUAL, save_to_played_slot = TRUE)
	return TRUE

UI_ACT(/datum/shadekin, "adjust_color", ui_act_adjust_color)
UI_ACT_PROC(/datum/shadekin, ui_act_adjust_color)
	om_ask(ui.user, /datum/om/prompt/color, PROC_REF(flicker_color_picked), message = "Select a color you wish the lights to flicker as (Default is #E0EFF0)", default = flicker_color, ui_refresh = src, title = "Color Selector")
	return FALSE

UI_ACT(/datum/shadekin, "adjust_break", ui_act_adjust_break, UI_ARG_NUM("val"))
UI_ACT_PROC(/datum/shadekin, ui_act_adjust_break)
	var/new_break_chance = params["val"]
	new_break_chance = CLAMP(new_break_chance, 0, 25)
	if(!isnum(new_break_chance))
		return FALSE
	flicker_break_chance = new_break_chance
	ui.user.write_preference_directly(/datum/preference/numeric/living/flicker_break_chance, new_break_chance, WRITE_PREF_MANUAL, save_to_played_slot = TRUE)
	return TRUE

UI_ACT(/datum/shadekin, "adjust_distance", ui_act_adjust_distance, UI_ARG_NUM("val"))
UI_ACT_PROC(/datum/shadekin, ui_act_adjust_distance)
	var/new_distance = params["val"]
	new_distance = CLAMP(new_distance, 4, 10)
	if(!isnum(new_distance))
		return FALSE
	flicker_distance = new_distance
	ui.user.write_preference_directly(/datum/preference/numeric/living/flicker_distance, new_distance, WRITE_PREF_MANUAL, save_to_played_slot = TRUE)
	return TRUE

UI_ACT(/datum/shadekin, "toggle_retreat", ui_act_toggle_retreat)
UI_ACT_PROC(/datum/shadekin, ui_act_toggle_retreat)
	var/new_retreat = !no_retreat
	no_retreat = !no_retreat
	ui.user.write_preference_directly(/datum/preference/toggle/living/dark_retreat_toggle, new_retreat, WRITE_PREF_MANUAL, save_to_played_slot = TRUE)

UI_ACT(/datum/shadekin, "toggle_nutrition", ui_act_toggle_nutrition)
UI_ACT_PROC(/datum/shadekin, ui_act_toggle_nutrition)
	var/new_retreat = !nutrition_energy_conversion
	nutrition_energy_conversion = !nutrition_energy_conversion
	ui.user.write_preference_directly(/datum/preference/toggle/living/shadekin_nutrition_conversion, new_retreat, WRITE_PREF_MANUAL, save_to_played_slot = TRUE)

UI_ACT(/datum/shadekin, "toggle_voice", ui_act_toggle_voice)
UI_ACT_PROC(/datum/shadekin, ui_act_toggle_voice)
	var/new_voice_hide = !hide_voice_in_phase
	hide_voice_in_phase = !hide_voice_in_phase
	ui.user.write_preference_directly(/datum/preference/toggle/living/shadekin_hide_voice_in_phase, new_voice_hide, WRITE_PREF_MANUAL, save_to_played_slot = TRUE)

/// The voice answer of GetVoice(): phase-shifted shadekin who hide their voice are "Something". The handler's value is the voice (the act's reply).
/datum/shadekin/proc/on_get_voice(datum/act/name_voice/voice)
	EVENT_HANDLER
	if(in_phase && hide_voice_in_phase)
		return "Something"
	return HOOK_DECLINE

/// The alt name answer of GetAltName(): no alt name while hidden in phase, and none for shadekin with voice changers or no identification.
/datum/shadekin/proc/on_get_alt_name(datum/act/name_alt/alt)
	EVENT_HANDLER
	var/mob/living/carbon/human/source = alt.target
	if(in_phase && hide_voice_in_phase)
		return ""

	// Suppress "(as Unknown)" for shadekin with voice changers, or no identification.
	if(source.name != source.GetVoice())
		return ""
	return HOOK_DECLINE

/// The visible name answer of get_visible_name().
/datum/shadekin/proc/on_get_visible_name(datum/act/name_visible/shown)
	EVENT_HANDLER
	if(in_phase && hide_voice_in_phase)
		return "Something"
	return HOOK_DECLINE

/mob/living/proc/shadekin_control_panel()
	set name = "Shadekin Control Panel"
	set desc = "Allows you to adjust the settings of various shadekin settings!"
	set category = VERB_CAT_ABILITIES_SHADEKIN

	var/datum/shadekin/SK = get_shadekin_state()
	if(!SK)
		to_chat(src, span_warning("Only a shadekin can use that!"))
		return FALSE

	SK.tgui_interact(src)

/// Trait system: shadekin energy for non-human mobs.
/datum/om/stage/life/trait/shadekin
	name = "shadekin"

/datum/om/stage/life/trait/shadekin/perform(mob/living/self, datum/om/frame/life/ctx)
	self.shadekin?.handle_comp()

CAPABILITIES(/datum/shadekin)
	ref_many(nameof(active_dark_maws))

/// Constant ability ids shared by every instance of the same concrete type.
TYPE_TABLE_DECLARE(/datum/shadekin, shadekin_ability_ids, list(ABILITY_ID_SHADEKIN_PHASE_SHIFT, ABILITY_ID_SHADEKIN_REGENERATE_OTHER, ABILITY_ID_SHADEKIN_CREATE_SHADE))
TYPE_TABLE(/datum/shadekin/phase_only, shadekin_ability_ids, list(ABILITY_ID_SHADEKIN_PHASE_SHIFT))
TYPE_TABLE(/datum/shadekin/full, shadekin_ability_ids, list(ABILITY_ID_SHADEKIN_PHASE_SHIFT, ABILITY_ID_SHADEKIN_REGENERATE_OTHER, ABILITY_ID_SHADEKIN_CREATE_SHADE, ABILITY_ID_SHADEKIN_DARK_RESPITE, ABILITY_ID_SHADEKIN_DARK_TUNNELING, ABILITY_ID_SHADEKIN_DARK_MAW, ABILITY_ID_SHADEKIN_CLEAR_DARK_MAWS))

/datum/shadekin/proc/granted_ability_ids()
	return TYPE_TABLE_GET(src, shadekin_ability_ids)
