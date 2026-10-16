/datum/vore_look/proc/get_preference_data(mob/owner)
	return list(
		"digestable" = owner.vore_prefs.digestable,
		"devourable" = owner.vore_prefs.devourable,
		"resizable" = owner.vore_prefs.resizable,
		"feeding" = owner.vore_prefs.feeding,
		"absorbable" = owner.vore_prefs.absorbable,
		"digest_leave_remains" = owner.vore_prefs.digest_leave_remains,
		"allowmobvore" = owner.vore_prefs.allowmobvore,
		"allowtemp" = owner.vore_prefs.allowtemp,
		"permit_healbelly" = owner.vore_prefs.permit_healbelly,
		"show_vore_fx" = owner.vore_prefs.show_vore_fx,
		"can_be_drop_prey" = owner.vore_prefs.can_be_drop_prey,
		"can_be_drop_pred" = owner.vore_prefs.can_be_drop_pred,
		"can_be_afk_prey" = owner.vore_prefs.can_be_afk_prey,
		"can_be_afk_pred" = owner.vore_prefs.can_be_afk_pred,
		"latejoin_vore" = owner.vore_prefs.latejoin_vore,
		"latejoin_prey" = owner.vore_prefs.latejoin_prey,
		"no_spawnpred_warning" = owner.vore_prefs.no_latejoin_vore_warning,
		"no_spawnprey_warning" = owner.vore_prefs.no_latejoin_prey_warning,
		"no_spawnpred_warning_time" = owner.vore_prefs.no_latejoin_vore_warning_time,
		"no_spawnprey_warning_time" = owner.vore_prefs.no_latejoin_prey_warning_time,
		"no_spawnpred_warning_save" = owner.vore_prefs.no_latejoin_vore_warning_persists,
		"no_spawnprey_warning_save" = owner.vore_prefs.no_latejoin_prey_warning_persists,
		"allow_spontaneous_tf" = owner.vore_prefs.allow_spontaneous_tf,
		"step_mechanics_active" = owner.vore_prefs.step_mechanics_pref,
		"pickup_mechanics_active" = owner.vore_prefs.pickup_pref,
		"strip_mechanics_active" = owner.vore_prefs.strip_pref,
		"contaminate_worn_items" = owner.vore_prefs.contaminate_pref,
		"noisy" = owner.vore_prefs.noisy,
		//liquid belly prefs
		"liq_rec" = owner.vore_prefs.receive_reagents,
		"liq_giv" = owner.vore_prefs.give_reagents,
		"liq_apply" = owner.vore_prefs.apply_reagents,
		"autotransferable" = owner.autotransferable,
		"noisy_full" = owner.vore_prefs.noisy_full, //Belching while full

		"allow_mind_transfer" = owner.vore_prefs.allow_mind_transfer,
		"drop_vore" = owner.vore_prefs.drop_vore,
		"slip_vore" = owner.vore_prefs.slip_vore,
		"stumble_vore" = owner.vore_prefs.stumble_vore,
		"throw_vore" = owner.vore_prefs.throw_vore,
		"phase_vore" = owner.vore_prefs.phase_vore,
		"food_vore" = owner.vore_prefs.food_vore,
		"spont_belly_rear" = owner.spont_belly_rear,
		"spont_belly_left" = owner.spont_belly_left,
		"spont_belly_front" = owner.spont_belly_front,
		"spont_belly_right" = owner.spont_belly_right,
		"consume_liquid_belly" = owner.vore_prefs.consume_liquid_belly,
		"digest_pain" = owner.vore_prefs.digest_pain,
		"eating_privacy_global" = owner.vore_prefs.eating_privacy_global,
		"vore_death_privacy" = owner.vore_prefs.vore_death_privacy,
		"allow_mimicry" = owner.vore_prefs.allow_mimicry,
		//Soulcatcher
		"soulcatcher_allow_capture" = owner.vore_prefs.soulcatcher_pref_flags & SOULCATCHER_ALLOW_CAPTURE,
		"soulcatcher_allow_transfer" = owner.vore_prefs.soulcatcher_pref_flags & SOULCATCHER_ALLOW_TRANSFER,
		"soulcatcher_allow_takeover" = owner.vore_prefs.soulcatcher_pref_flags & SOULCATCHER_ALLOW_TAKEOVER,
		"soulcatcher_allow_deletion" = (global_flag_check(owner.vore_prefs.soulcatcher_pref_flags, SOULCATCHER_ALLOW_DELETION) + global_flag_check(owner.vore_prefs.soulcatcher_pref_flags, SOULCATCHER_ALLOW_DELETION_INSTANT)),
		"max_voreoverlay_alpha" = owner.vore_prefs.max_voreoverlay_alpha,
		"dropdown_preferences" = list(
			"strip_active" = owner.vore_prefs.size_strip_preference,
			"selective_active" = owner.vore_prefs.selective_preference, //Reveal active selective mode in prefs
		)
	)

#define SET_TASTE "Set Taste"
#define SET_SMELL "Set Smell"
#define SET_NUTRITION_EX "Set Nutrition Examine"
#define SET_WEIGHT_EX "Set Weight Examine"

/datum/vore_look/proc/get_general_data(mob/owner)
	return list(
		"active_belly" = vore_selected_of(owner)?.name,
		"belly_rub_target" = owner.vore_prefs.belly_rub_target,
		// start, vore sprites
		"aestethic_messages" = compile_aesthetic_messages(owner),
		"vore_sprite_color" = owner.vore_prefs.vore_sprite_color,
		"vore_sprite_multiply" = owner.vore_prefs.vore_sprite_multiply,
		"vore_icon_options" = owner.vore_icon_bellies,
		// spont options
		"spont_rear" = owner.spont_belly_rear,
		"spont_front" = owner.spont_belly_front,
		"spont_left" = owner.spont_belly_left,
		"spont_right" = owner.spont_belly_right
	)

/datum/vore_look/proc/compile_aesthetic_messages(mob/owner)
	if(!aset_message_subtab)
		set_aset_message_subtab(SET_TASTE)
	var/list/tab_data = list(
		"possible_messages" = list(SET_TASTE, SET_SMELL, SET_NUTRITION_EX, SET_WEIGHT_EX),
		"aest_subtab" = aset_message_subtab
		)
	switch(aset_message_subtab)
		if(SET_TASTE)
			tab_data["max_length"] = FLAVOR_MAX
			tab_data["active_message"] = owner.vore_prefs.vore_taste
			tab_data["set_action"] = TASTE_FLAVOR
			tab_data["tooltip"] = "What your character tastes like. This text will be printed to the pred after 'X tastes of...' so just put something like 'strawberries and cream'"
		if(SET_SMELL)
			tab_data["max_length"] = FLAVOR_MAX
			tab_data["active_message"] = owner.vore_prefs.vore_smell
			tab_data["set_action"] = SMELL_FLAVOR
			tab_data["tooltip"] = "What your character smells like. This text will be printed to the pred after 'X smells of...' so just put something like 'strawberries and cream'"
		if(SET_NUTRITION_EX)
			tab_data["max_length"] = BELLIES_EXAMINE_MAX
			tab_data["active_message"] = owner.vore_prefs.nutrition_messages
			tab_data["set_action"] = "set_attribute"
			tab_data["sub_action"] = GENERAL_EXAMINE_NUTRI
			tab_data["tooltip"] = "Change the nutrition display messages on examine."
			tab_data["button_label"] = "Display Nutrition Examine"
			tab_data["button_action"] = "toggle_nutrition_ex"
			tab_data["button_data"] = owner.vore_prefs.nutrition_message_visible
			tab_data["button_tooltip"] = "the nutition messages on examine." // those will automatically be preceeded by Enables / Disables!
		if(SET_WEIGHT_EX)
			tab_data["max_length"] = BELLIES_EXAMINE_MAX
			tab_data["active_message"] = owner.vore_prefs.weight_messages
			tab_data["set_action"] = "set_attribute"
			tab_data["sub_action"] = GENERAL_EXAMINE_WEIGHT
			tab_data["tooltip"] = "Change the weight display messages on examine."
			tab_data["button_label"] = "Display Weight Examine"
			tab_data["button_action"] = "toggle_weight_ex"
			tab_data["button_data"] = owner.vore_prefs.weight_message_visible
			tab_data["button_tooltip"] = "the weight messages on examine." // those will automatically be preceeded by Enables / Disables!
	return tab_data

#undef SET_TASTE
#undef SET_SMELL
#undef SET_NUTRITION_EX
#undef SET_WEIGHT_EX
