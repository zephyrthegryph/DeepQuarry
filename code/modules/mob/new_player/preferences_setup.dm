/datum/preferences

/datum/preferences/proc/randomise_appearance_prefs_update(randomize_flags = ALL, datum/species/current_species)
	randomise_appearance_prefs(randomize_flags, current_species)

/datum/preferences/proc/randomise_appearance_prefs_write(randomize_flags = ALL, datum/species/current_species)
	randomise_appearance_prefs(randomize_flags, current_species, TRUE)

/// Fully randomizes everything in the character.
/datum/preferences/proc/randomise_appearance_prefs(randomize_flags = ALL, datum/species/current_species, write = FALSE)
	for (var/datum/preference/preference as anything in get_preferences_in_priority_order())
		if (!preference.included_in_randomization_flags(randomize_flags))
			continue
		if (preference.is_randomizable())
			if(write)
				write_preference(preference, preference.create_random_value(src, current_species))
			else
				update_preference(preference, preference.create_random_value(src, current_species))

/* Currently not used
/// Randomizes the character according to preferences.
/datum/preferences/proc/apply_character_randomization_prefs(antag_override = FALSE)
	switch (read_preference(/datum/preference/choiced/random_body))
		if (RANDOM_ANTAG_ONLY)
			if (!antag_override)
				return

		if (RANDOM_DISABLED)
			return

	for (var/datum/preference/preference as anything in get_preferences_in_priority_order())
		if (should_randomize(preference, antag_override))
			write_preference(preference, preference.create_random_value(src))
*/



/datum/preferences/proc/randomize_hair_color(target = "hair")
	if(prob (75) && target == "facial") // Chance to inherit hair color
		update_preference_by_type(/datum/preference/color/human/facial_color, read_preference(/datum/preference/color/human/hair_color))
		return

	var/red
	var/green
	var/blue

	var/col = pick ("blonde", "black", "chestnut", "copper", "brown", "wheat", "old", "punk")
	switch(col)
		if("blonde")
			red = 255
			green = 255
			blue = 0
		if("black")
			red = 0
			green = 0
			blue = 0
		if("chestnut")
			red = 153
			green = 102
			blue = 51
		if("copper")
			red = 255
			green = 153
			blue = 0
		if("brown")
			red = 102
			green = 51
			blue = 0
		if("wheat")
			red = 255
			green = 255
			blue = 153
		if("old")
			red = rand (100, 255)
			green = red
			blue = red
		if("punk")
			red = rand (0, 255)
			green = rand (0, 255)
			blue = rand (0, 255)

	red = max(min(red + rand (-25, 25), 255), 0)
	green = max(min(green + rand (-25, 25), 255), 0)
	blue = max(min(blue + rand (-25, 25), 255), 0)

	switch(target)
		if("hair")
			update_preference_by_type(/datum/preference/color/human/hair_color, rgb(red, green, blue))
		if("facial")
			update_preference_by_type(/datum/preference/color/human/facial_color, rgb(red, green, blue))

/datum/preferences/proc/randomize_eyes_color()
	var/red
	var/green
	var/blue

	var/col = pick ("black", "grey", "brown", "chestnut", "blue", "lightblue", "green", "albino")
	switch(col)
		if("black")
			red = 0
			green = 0
			blue = 0
		if("grey")
			red = rand (100, 200)
			green = red
			blue = red
		if("brown")
			red = 102
			green = 51
			blue = 0
		if("chestnut")
			red = 153
			green = 102
			blue = 0
		if("blue")
			red = 51
			green = 102
			blue = 204
		if("lightblue")
			red = 102
			green = 204
			blue = 255
		if("green")
			red = 0
			green = 102
			blue = 0
		if("albino")
			red = rand (200, 255)
			green = rand (0, 150)
			blue = rand (0, 150)

	red = max(min(red + rand (-25, 25), 255), 0)
	green = max(min(green + rand (-25, 25), 255), 0)
	blue = max(min(blue + rand (-25, 25), 255), 0)

	update_preference_by_type(/datum/preference/color/human/eyes_color, rgb(red, green, blue))

/datum/preferences/proc/randomize_skin_color()
	var/red
	var/green
	var/blue

	var/col = pick ("black", "grey", "brown", "chestnut", "blue", "lightblue", "green", "albino")
	switch(col)
		if("black")
			red = 0
			green = 0
			blue = 0
		if("grey")
			red = rand (100, 200)
			green = red
			blue = red
		if("brown")
			red = 102
			green = 51
			blue = 0
		if("chestnut")
			red = 153
			green = 102
			blue = 0
		if("blue")
			red = 51
			green = 102
			blue = 204
		if("lightblue")
			red = 102
			green = 204
			blue = 255
		if("green")
			red = 0
			green = 102
			blue = 0
		if("albino")
			red = rand (200, 255)
			green = rand (0, 150)
			blue = rand (0, 150)

	red = max(min(red + rand (-25, 25), 255), 0)
	green = max(min(green + rand (-25, 25), 255), 0)
	blue = max(min(blue + rand (-25, 25), 255), 0)

	update_preference_by_type(/datum/preference/color/human/skin_color, rgb(red, green, blue))

/datum/preferences/proc/dress_preview_mob(mob/living/carbon/human/mannequin)
	if(!mannequin.dna) // Special handling for preview icons before SSAtoms has initailized.
		mannequin.dna = new /datum/dna(null)
	copy_to(mannequin, TRUE)

	// DQEdit Start — equip_preview_mob bitfield replaced by two toggles. Keep the same
	// boolean shape so the rest of this proc is untouched.
	var/_preview_loadout = read_preference(/datum/preference/toggle/human/preview_loadout)
	var/_preview_job     = read_preference(/datum/preference/toggle/human/preview_job)
	if(!_preview_loadout && !_preview_job)
		return
	// DQEdit End

	// DQEdit — was 25 lines of department-switch logic duplicated with get_highest_job().
	// Single call now; the visitor sentinel is the explicit prefer_visitor_role pref. For
	// the preview the visitor case wants JOB_ALT_VISITOR rather than the get_highest_job
	// fallback of JOB_ALT_ASSISTANT, so handle that special case here. Fall back to
	// Intern for new players with no priorities so the preview shows the default kit.
	//
	// Loadout-key override: when the player is editing a per-job loadout (e.g. Captain),
	// the preview should reflect THAT job's effective kit, not whatever their highest
	// priority happens to be. Otherwise editing the Captain loadout previews as Intern
	// and the Captain-only items don't show. Default loadout falls through to the
	// normal highest-job resolution.
	var/datum/job/previewJob
	if(client && ispAI(client.mob))
		previewJob = null  // pAI clients get no preview job equip.
	else if(read_preference(/datum/preference/toggle/human/prefer_visitor_role))
		previewJob = SSjob.get_job(JOB_ALT_VISITOR)
	else
		var/_loadout_key = read_preference(/datum/preference/text/human/gear_slot)
		var/datum/job/loadout_target_job
		if(istext(_loadout_key) && _loadout_key != "_default")
			loadout_target_job = SSjob.get_job(_loadout_key)
		previewJob = loadout_target_job || get_highest_job() || SSjob.get_job(JOB_INTERN)

	// DQEdit Start — equip job FIRST, then loadout. Previously the order was loadout-then-job,
	// but `mob_can_equip` rejects equipping into an occupied slot AND `equip_to_slot_or_del`
	// silently qdels the rejected item, so a job whose outfit overlapped a loadout slot was
	// trying to (correctly) refuse to equip — but in practice some items still bled through
	// due to subtle equip ordering bugs. Equipping the job first and then the loadout means
	// the loadout layer is unambiguously "on top" and the player's customisations always win.
	if(_preview_job && previewJob)
		mannequin.job = previewJob.title
		var/list/alt_titles = read_preference(/datum/preference/player_alt_titles)
		previewJob.equip_preview(mannequin, islist(alt_titles) ? alt_titles[previewJob.title] : null)

	if(_preview_loadout && !(previewJob && _preview_job && (previewJob.type == /datum/job/ai || previewJob.type == /datum/job/cyborg)))
		// DQEdit — migrated gear_list/gear_slot
		var/list/equipped_slots = list()
		// DQEdit — per-job loadout. Use the preview job's title to pick the right loadout
		// list, falling back to "_default". Was: gear_list[gear_slot] (single shared list).
		var/list/active_gear_list = get_loadout_for_job(previewJob ? previewJob.title : null)
		for(var/thing in active_gear_list)
			var/datum/gear/G = GLOB.gear_datums[thing]
			if(G)
				var/permitted = 0
				if(!G.allowed_roles)
					permitted = 1
				else if(!previewJob)
					permitted = 0
				else
					for(var/job_name in G.allowed_roles)
						if(previewJob.title == job_name)
							permitted = 1

				if(G.whitelisted && (G.whitelisted != mannequin.species.name && G.whitelisted != mannequin.species.base_species))
					permitted = 0

				if(!permitted)
					continue

				if(G.slot && !(G.slot in equipped_slots))
					// Evict whatever the job equipped here so the loadout item takes priority.
					// Skip eviction for slot_tie since it's the multi-allowed accessory slot.
					if(G.slot != slot_tie)
						var/obj/item/existing = mannequin.get_equipped_item(G.slot)
						if(existing)
							mannequin.drop_from_inventory(existing)
							qdel(existing)
					var/metadata = active_gear_list[G.display_name]
					if(mannequin.equip_to_slot_or_del(G.spawn_item(mannequin, metadata), G.slot))
						if(G.slot != slot_tie)
							equipped_slots += G.slot
	// DQEdit End

// DQAdd — Preview rebuild runs synchronously so pref changes feel instant; only
// the static_data PUSH to tgui viewers is deferred. The push is what was hitting
// BYOND's recursion limit on size_multiplier — send_full_update + tgui_static_data
// + middleware.get_ui_static_data walks every editor catalog AND every pref via
// compile_character_preferences. Combined with the apply pipeline depth from
// /mob/living/carbon/human/update_transform on a size change, it tipped over.
//
// Splitting the work:
//   1. update_preview_icon() — synchronous rebuild of character_preview_b64
//      (apply pipeline + getFlatIcon × 4). Stays inside update_preference's
//      call stack, but isn't itself recursive.
//   2. After the rebuild, mark "push pending" and addtimer the actual
//      send_full_update fan-out. The push runs on a fresh stack one tick later.
//
// Multiple rapid pref changes coalesce because both the addtimer call uses
// TIMER_UNIQUE | TIMER_OVERRIDE and the dq_push_pending guard skips re-queuing
// if a push is already on its way.

/datum/preferences/proc/update_preview_icon_lazy()
	if(updating_preview_icon)
		return
	update_preview_icon(south_only = TRUE)
	addtimer(CALLBACK(src, TYPE_PROC_REF(/datum/preferences, update_preview_icon)), 1, TIMER_UNIQUE | TIMER_OVERRIDE)

/datum/preferences/proc/update_preview_icon(south_only = FALSE)
	// Re-entry guard. apply_hooks shouldn't write prefs via update_preference,
	// but if they do, the second call sees the guard set and bails.
	if(updating_preview_icon)
		return
	updating_preview_icon = TRUE
	try
		dq_render_preview(south_only)
	catch(var/exception/e)
		stack_trace("update_preview_icon runtimed: [e.name] at [e.file]:[e.line]")
	updating_preview_icon = FALSE
	// Schedule the static_data push. Coalesces rapid calls via TIMER_UNIQUE +
	// the dq_push_pending guard. Always runs on a fresh stack so the heavy
	// send_full_update path can't add to the apply pipeline's depth.
	dq_schedule_static_push()

/datum/preferences/proc/dq_schedule_static_push()
	if(dq_preview_pending)
		return
	dq_preview_pending = TRUE
	addtimer(CALLBACK(src, TYPE_PROC_REF(/datum/preferences, dq_flush_static_push)), 0, TIMER_UNIQUE | TIMER_OVERRIDE)

/datum/preferences/proc/dq_flush_static_push()
	dq_preview_pending = FALSE
	update_static_data_for_all_viewers()

/datum/preferences/proc/dq_render_preview(south_only = FALSE)
	var/play_mode = read_preference(/datum/preference/text/human/play_mode) || "human"
	if(play_mode == "robot")
		dq_update_robot_preview(south_only)
		return
	if(play_mode == "pai")
		dq_update_pai_preview(south_only)
		return
	var/mob/living/carbon/human/dummy/mannequin/mannequin = get_mannequin(client_ckey)
	if(!mannequin.dna)
		mannequin.dna = new /datum/dna(null)
	mannequin.delete_inventory(TRUE)
	dress_preview_mob(mannequin)
	mannequin.update_transform()
	var/_animations_toggle = read_preference(/datum/preference/toggle/human/animations_toggle)
	mannequin.toggle_tail(setting = _animations_toggle)
	mannequin.toggle_wing(setting = _animations_toggle)
	update_character_previews(mannequin, south_only)

// DQEdit — get_highest_job() moved to
// modular_dq/code/modules/client/preferences/types/character/job_priorities.dm. It now
// reads from /datum/preference/job_priorities (one sparse assoc) and respects
// prefer_visitor_role, replacing the bucket-by-department_flag switch that lived here.

/datum/preferences/proc/get_valid_hairstyles(mob/user)
	var/list/valid_hairstyles = list()
	var/pref_species = read_preference(/datum/preference/choiced/species)
	for(var/hairstyle in GLOB.hair_styles_list)
		var/datum/sprite_accessory/S = GLOB.hair_styles_list[hairstyle]
		if(S.name == DEVELOPER_WARNING_NAME)
			continue
		if(!(pref_species in S.species_allowed) && (!read_preference(/datum/preference/text/human/custom_base) || !(read_preference(/datum/preference/text/human/custom_base) in S.species_allowed))) // DQEdit — migrated
			continue
		if(!S.can_be_selected && (!client || !check_rights_for(client, R_HOLDER)))
			continue
		if((!S.ckeys_allowed) || (user.ckey in S.ckeys_allowed))
			valid_hairstyles[S.name] = hairstyle


	return valid_hairstyles

/datum/preferences/proc/get_valid_facialhairstyles()
	var/list/valid_facialhairstyles = list()
	var/bio_gender = read_preference(/datum/preference/choiced/gender/biological)
	var/pref_species = read_preference(/datum/preference/choiced/species)
	for(var/facialhairstyle in GLOB.facial_hair_styles_list)
		var/datum/sprite_accessory/S = GLOB.facial_hair_styles_list[facialhairstyle]
		if(S.name == DEVELOPER_WARNING_NAME)
			continue
		if(bio_gender == MALE && S.gender == FEMALE)
			continue
		if(bio_gender == FEMALE && S.gender == MALE)
			continue
		if(!(pref_species in S.species_allowed) && (!read_preference(/datum/preference/text/human/custom_base) || !(read_preference(/datum/preference/text/human/custom_base) in S.species_allowed))) // DQEdit — migrated
			continue
		if(!S.can_be_selected && (!client || !check_rights_for(client, R_HOLDER)))
			continue

		valid_facialhairstyles[facialhairstyle] = GLOB.facial_hair_styles_list[facialhairstyle]

	return valid_facialhairstyles
