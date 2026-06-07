GLOBAL_LIST_EMPTY(preferences_datums)

/datum/preferences
	/// The path to the general savefile for this datum
	var/path
	/// Whether or not we allow saving/loading. Used for guests, if they're enabled
	var/load_and_save = TRUE
	/// Ensures that we always load the last used save, QOL
	var/default_slot = 1

	//non-preference stuff
	var/warns = 0
	var/muted = 0
	var/last_ip
	var/last_id
	var/saved_notification = FALSE

	//game-preferences
	var/lastchangelog = ""				//Saved changlog filesize to detect if there was a change // CHOMPAdd

	// DQEdit — be_special, b_type, blood_reagents, headset, backbag, pdachoice, no_jacket,
	// h_style, grad_style, f_style, s_tone, alternate_languages, language_prefixes,
	// language_custom_keys, gear_list, gear_slot, traits (legacy alias), synth_color,
	// synth_markings, digitigrade, antag_faction, antag_vis all migrated to /datum/preference
	// subtypes. species_preview was unused; deleted.

		//Mob preview
	// DQEdit — replaced the BYOND map control approach entirely. Instead of
	// rendering the mannequin onto a map element via screen objects, we
	// flatten the mannequin (4 directions) and the BG into base-64 PNGs
	// via getFlatIcon + icon2base64 and ship them in tgui_data. React
	// displays them as scaled <img> tags. This sidesteps the unreliable
	// BYOND dynamic-map-element creation path (icon-size honoring race,
	// the "sometimes tiny" symptom) and gives us deterministic sizing.
	//
	// character_preview_b64 is an assoc list: "south"/"north"/"east"/"west"
	// → base-64 string for the mannequin facing that direction; "bg" → the
	// background icon's base-64 string. Rebuilt by update_character_previews
	// every time update_preview_icon runs (every pref change).
	var/list/character_preview_b64

	//character preferences
	var/slot_randomized //keeps track of round-to-round randomization of the character slot, prevents overwriting

	var/list/randomise = list()

	// maps each organ to either null(intact), "cyborg" or "amputated"
	// will probably not be able to do this for head and torso ;)

	// DQEdit — body_markings, flavor_texts, flavour_texts_robot, custom_link, exploit_record migrated to /datum/preference subtypes.

	var/client/client = null
	var/client_ckey = null

	// DQEdit — communicator_visibility/ringtone migrated to /datum/preference subtypes.

	// DQEdit — Bay player_setup chain deleted; per-pref sanitize/save/load handles
	// everything. /datum/browser/panel also removed (tgui-migration replaces all
	// browse()/datum/browser usage).

	var/lastnews // Hash of last seen lobby news content.
	var/lastlorenews //ID of last seen lore news article.

	// THIS IS NOT SAVED
	// WE JUST HAVE NOWHERE ELSE TO STORE IT
	var/list/action_button_screen_locs

	///If they are currently in the process of swapping slots, don't let them open 999 windows for it and get confused
	var/selecting_slots = FALSE

	/// The json savefile for this datum
	var/datum/json_savefile/savefile

	// DQAdd — when non-zero, defers save flushes inside a transactional update_many() block.
	var/save_batch_depth = 0
	/// Set when at least one save would have fired during the current batch.
	var/save_batch_dirty = FALSE
	/// Depth counter for nested constraint cascades. The runner refuses to recurse past
	/// PREF_CONSTRAINT_MAX_DEPTH so a constraint that triggers itself (directly or
	/// transitively through another constraint) crashes loudly instead of stack-bombing.
	var/constraint_cascade_depth = 0
	/// Re-entry guard for update_preview_icon(). apply_hooks that write prefs as a side
	/// effect would otherwise re-trigger preview generation and infinite-recurse.
	var/updating_preview_icon = FALSE
	/// DQAdd — Guard for the deferred static_data push (full update — used
	/// when an editor cache entry was invalidated, e.g. species change drops
	/// loadout's catalog). Coalesces multiple invalidations in one tick.
	var/dq_preview_pending = FALSE
	/// DQAdd — Guard for the deferred ui_data push (data-only update — used
	/// for routine pref edits, slider drags, etc. that only need to refresh
	/// the preview assets / pref values). Avoids the heavy reconciliation
	/// that send_full_update would trigger.
	var/dq_data_push_pending = FALSE
	/// DQAdd — Cache of editor static_data payloads ({editor_key → list}).
	/// Built lazily by the character_setup middleware's get_ui_static_data.
	/// Invalidated by update_preference when a structural pref changes (see
	/// GLOB.dq_editor_static_invalidator_keys). null means "not built yet".
	var/list/dq_editor_static_cache = null
	/// DQAdd — Guard against scheduling multiple deferred cache builds when
	/// get_ui_static_data is called repeatedly before the first build lands.
	var/dq_static_pending = FALSE

/datum/preferences/New(client/C)
	client = C

	for(var/middleware_type in subtypesof(/datum/preference_middleware))
		middleware += new middleware_type(src)

	if(istype(C)) // IS_CLIENT_OR_MOCK
		client_ckey = C.ckey
		load_and_save = !IsGuestKey(C.key)
		load_path(C.ckey)
		// DQEdit — no legacy BYOND savefile migration on this fork.
	else
		CRASH("attempted to create a preferences datum without a client or mock!")
	load_savefile()

	// DQEdit — Bay player_setup instantiation deleted; new system needs no setup datum.

	var/loaded_preferences_successfully = load_preferences()
	if(loaded_preferences_successfully)
		if(load_character())
			return

	// Didn't load a character, so let's randomize
	set_biological_gender(pick(MALE, FEMALE))
	update_preference_by_type(/datum/preference/name/real_name, random_name(read_preference(/datum/preference/choiced/gender/identifying), read_preference(/datum/preference/choiced/species)))
	update_preference_by_type(/datum/preference/text/human/b_type, RANDOM_BLOOD_TYPE) // DQEdit — migrated

	if(client)
		apply_all_client_preferences()

	if(!loaded_preferences_successfully)
		save_preferences()
	save_character() // Save random character

/datum/preferences/Destroy()
	// DQEdit — character_preview_b64 is just a list of base64 strings, no
	// atoms to qdel.
	character_preview_b64 = null
	// DQEdit — `middleware` is a list of /datum/preference_middleware; QDEL_NULL would
	// pass the list itself to qdel and trip the "lists should not be qdel'd" runtime.
	// QDEL_LIST iterates and qdels each entry then clears the list.
	QDEL_LIST(middleware)
	value_cache = null
	return ..()

// DQAdd Start — transactional batching for constraint cascades and editor actions.
// Wrap multiple update_preference() calls in update_many(); all the writes are coalesced
// into a single save flush at the end. Calls nest safely.
/datum/preferences/proc/begin_update_batch()
	save_batch_depth += 1

/datum/preferences/proc/end_update_batch()
	save_batch_depth -= 1
	if(save_batch_depth < 0)
		stack_trace("end_update_batch() called more times than begin_update_batch() on [client_ckey]'s prefs")
		save_batch_depth = 0
	if(save_batch_depth == 0 && save_batch_dirty)
		save_batch_dirty = FALSE
		save_character()
		save_preferences()
// DQAdd End

/datum/preferences/proc/ShowChoices(mob/user)
	if(!user || !user.client)
		return

	if(!get_mob_by_key(client_ckey))
		to_chat(user, span_danger("No mob exists for the given client!"))
		return

	// DQEdit — refresh the body appearance + base64 assets before tgui opens.
	// Preview build is the dominant cost of opening the window
	// (~500-1500ms for a fully-dressed mannequin × 4 directions). Defer the
	// north/east/west renders to a spawn() so the window paints with the
	// south frame immediately; the remaining directions stream in via the
	// next ui_data poll (preview_assets live in ui_data, see preferences_tgui.dm).
	current_window = PREFERENCE_TAB_CHARACTER_PREFERENCES
	if(!character_preview_b64)
		update_preview_icon_lazy()
	tgui_interact(user)

// DQEdit Start — asset-based character preview. update_character_previews
// flattens the mannequin (one frame per cardinal direction) plus the BG
// into base-64 PNG strings via getFlatIcon + icon2base64 and stashes them
// on character_preview_b64. React displays them with <img> tags scaled by
// CSS — no BYOND map control involved, no icon-size race, deterministic
// sizing.
/datum/preferences/proc/update_character_previews(mob/living/carbon/human/mannequin, south_only = FALSE)
	if(!mannequin)
		return
	LAZYINITLIST(character_preview_b64)
	// DQEdit — bake size_multiplier + species icon scale into the flattened
	// PNG. getFlatIcon ignores the mannequin's matrix transform (that's how
	// in-world rendering applies size), so without this Scale() step the
	// preview ignores the size slider entirely.
	var/size_multiplier = read_preference(/datum/preference/numeric/human/size_multiplier) || 1
	var/scale_x = size_multiplier * (mannequin.species?.icon_scale_x || 1)
	var/scale_y = size_multiplier * (mannequin.species?.icon_scale_y || 1)
	var/list/dirs = south_only ? list("south" = SOUTH) : list("south" = SOUTH, "north" = NORTH, "east" = EAST, "west" = WEST)
	for(var/dir_key in dirs)
		var/dir = dirs[dir_key]
		mannequin.set_dir(dir)
		mannequin.update_tail_showing()
		mannequin.ImmediateOverlayUpdate()
		var/icon/flat = getFlatIcon(mannequin, defdir = dir, no_anim = TRUE)
		if(scale_x != 1 || scale_y != 1)
			flat.Scale(max(1, round(flat.Width() * scale_x)), max(1, round(flat.Height() * scale_y)))
		character_preview_b64[dir_key] = icon2base64(flat)
	var/bgstate = read_preference(/datum/preference/text/human/bgstate)
	if(bgstate)
		var/icon/bg_icon = icon('icons/effects/setup_backgrounds_vr.dmi', bgstate)
		character_preview_b64["bg"] = icon2base64(bg_icon)

/datum/preferences/proc/show_character_previews()
	return

/datum/preferences/proc/clear_character_previews()
	character_preview_b64 = null
// DQEdit End

/datum/preferences/proc/process_link(mob/user, list/href_list)
	if(!user)	return

	if(!isnewplayer(user))	return

	if(href_list["preference"] == "open_whitelist_forum")
		if(CONFIG_GET(string/forumurl))
			user << link(CONFIG_GET(string/forumurl))
		else
			to_chat(user, span_danger("The forum URL is not set in the server configuration."))
			return
	ShowChoices(user)
	return 1

/datum/preferences/Topic(href, list/href_list)
	if(..())
		return 1

	if(href_list["save"])
		if(save_character())
			to_chat(usr,span_notice("Character [read_preference(/datum/preference/name/real_name)] saved!")) // DQEdit — was player_setup.preferences.read_preference
		save_preferences()
	else if(href_list["reload"])
		load_preferences(TRUE)
		load_character()
		client.prefs_vr.load_vore()
		sanitize_preferences()
	else if(href_list["load"])
		if(!IsGuestKey(usr.key))
			open_load_dialog(usr)
			return 1
	else if(href_list["resetslot"])
		if("Yes" != tgui_alert(usr, "This will reset the current slot. Continue?", "Reset current slot?", list("No", "Yes")))
			return 0
		if("Yes" != tgui_alert(usr, "Are you completely sure that you want to reset this character slot?", "Reset current slot?", list("No", "Yes")))
			return 0
		reset_slot()
		sanitize_preferences()
	else if(href_list["copy"])
		if(!IsGuestKey(usr.key))
			open_copy_dialog(usr)
			return 1
	else if(href_list["close"])
		// User closed preferences window, cleanup anything we need to.
		clear_character_previews()
		//Mannequin removal code needed here...For the far future once harddels are solved.
		return 1
	else
		return 0

	ShowChoices(usr)
	return 1

/datum/preferences/proc/copy_to(mob/living/carbon/human/character, icon_updates = TRUE)
	// DQEdit — sanitize via the new registry-walking sanitize_preferences() instead of the
	// deleted Bay player_setup.sanitize_setup() chain.
	sanitize_preferences()

	// This needs to happen before anything else becuase it sets some variables.
	character.set_species(read_preference(/datum/preference/choiced/species))
	// Special Case: This references variables owned by two different datums, so do it here.
	if(read_preference(/datum/preference/toggle/human/name_is_always_random))
		// write_ instead of update_ to avoid update_preference_by_type calling copy_to again.
		write_preference_by_type(/datum/preference/name/real_name, random_name(read_preference(/datum/preference/choiced/gender/identifying), read_preference(/datum/preference/choiced/species)))

	// DQEdit — apply pipeline:
	//   1. Per-pref apply() walks every PREFERENCE_CHARACTER pref in priority order.
	//   2. /datum/preference_apply_hook subtypes run after, for cross-pref orchestration that
	//      doesn't fit a single pref (name sanitization, species/trait synthesis, organ apply,
	//      markings overlay rebuild, NIF spawn, body backup, finalize).
	//   Bay player_setup.copy_to_mob() is no longer called; all its logic has moved to
	//   per-pref apply_to_human and /datum/preference_apply_hook subtypes.
	for(var/datum/preference/preference as anything in get_preferences_in_priority_order())
		if(preference.savefile_identifier != PREFERENCE_CHARACTER)
			continue

		preference.apply(character, read_preference(preference.type), src)

	for(var/datum/preference_apply_hook/hook as anything in GLOB.preference_apply_hooks)
		if(hook.skip_on_preview && ismannequin(character))
			continue
		hook.apply(character, src)

	// Sync up all their organs one final time. force_update_limbs + regenerate_icons are
	// already handled by /datum/preference_apply_hook/finalize; we still need the body /
	// mutation / underwear / hair passes that aren't part of the hook.
	character.force_update_organs()

	if(icon_updates)
		character.update_icons_body()
		character.update_mutations()
		character.update_underwear()
		character.update_hair()

/datum/preferences/proc/open_load_dialog(mob/user)
	if(selecting_slots)
		to_chat(user, span_warning("You already have a slot selection dialog open!"))
		return
	if(!savefile)
		return

	var/default
	var/list/charlist = list()

	for(var/i in 1 to CONFIG_GET(number/character_slots))
		var/list/save_data = savefile.get_entry("character[i]", list())
		var/name = save_data["real_name"]
		var/nickname = save_data["nickname"]
		if(!name)
			name = "[i] - \[Unused Slot\]"
		else if(i == default_slot)
			name = "►[i] - [name]"
		else
			name = "[i] - [name]"
		if(i == default_slot)
			default = "[name][nickname ? " ([nickname])" : ""]"
		charlist["[name][nickname ? " ([nickname])" : ""]"] = i

	selecting_slots = TRUE
	var/choice = tgui_input_list(user, "Select a character to load:", "Load Slot", charlist, default)
	selecting_slots = FALSE
	if(!choice)
		return

	var/slotnum = charlist[choice]
	if(!slotnum)
		log_world("## ERROR Player picked [choice] slot to load, but that wasn't one we sent.")
		return

	load_preferences(TRUE)
	load_character(slotnum)
	user.client?.prefs_vr.load_vore()
	sanitize_preferences()
	save_preferences()
	ShowChoices(user)

/datum/preferences/proc/open_copy_dialog(mob/user)
	if(selecting_slots)
		to_chat(user, span_warning("You already have a slot selection dialog open!"))
		return
	if(!savefile)
		return

	var/list/charlist = list()

	for(var/i in 1 to CONFIG_GET(number/character_slots))
		var/list/save_data = savefile.get_entry("character[i]", list())
		var/name = save_data["real_name"]
		var/nickname = save_data["nickname"]

		if(!name)
			name = "[i] - \[Unused Slot\]"
		else if(i == default_slot)
			name = "►[i] - [name]"
		else
			name = "[i] - [name]"

		charlist["[name][nickname ? " ([nickname])" : ""]"] = i

	selecting_slots = TRUE
	var/choice = tgui_input_list(user, "Select a character to COPY TO:", "Copy Slot", charlist)
	selecting_slots = FALSE
	if(!choice)
		return

	var/slotnum = charlist[choice]
	if(!slotnum)
		log_world("## ERROR Player picked [choice] slot to copy to, but that wasn't one we sent.")
		return

	if(tgui_alert(user, "Are you sure you want to override slot [slotnum], [choice]'s savedata?", "Confirm Override", list("No", "Yes")) == "Yes")
		overwrite_character(slotnum)
		save_character(TRUE)
		save_preferences()
		load_preferences(TRUE)
		load_character()
		user.client?.prefs_vr.load_vore()
		ShowChoices(user)

// DQEdit — vanity_copy_to rewritten to ride the same /datum/preference apply pipeline as
// copy_to(), with a curated list of "vanity-scope" pref types so we only touch appearance/
// identity bits. The bool flags select which subsets get copied; the heavy lifting
// (species-filtered accessory resolution, markings overlay rebuild, name sanitization
// with surname injection) is delegated to the existing apply_hooks.
//
// This replaces what was a ~200-line snowflake duplicate-write proc.
/datum/preferences/proc/vanity_copy_to(mob/living/carbon/human/character, copy_name, copy_flavour = TRUE, copy_ooc_notes = FALSE, convert_to_prosthetics = FALSE, apply_bloodtype = TRUE)
	// Atomic batch so any constraint cascades from the writes below coalesce into one save.
	PREF_TRANSACTION_BEGIN(src)

	for(var/preference_type in GLOB.vanity_pref_types)
		// b_type is skipped unless apply_bloodtype; flavor_texts unless copy_flavour;
		// ooc_notes_* unless copy_ooc_notes; name/nickname unless copy_name.
		if(preference_type == /datum/preference/text/human/b_type && !apply_bloodtype)
			continue
		if(preference_type == /datum/preference/flavor_texts && !copy_flavour)
			continue
		if((preference_type == /datum/preference/name/real_name || preference_type == /datum/preference/name/nickname) && !copy_name)
			continue
		if(preference_type in GLOB.vanity_ooc_pref_types)
			if(!copy_ooc_notes)
				continue
		var/datum/preference/pref = GLOB.preference_entries[preference_type]
		if(!pref)
			continue
		pref.apply(character, read_preference(preference_type), src)

	// Cross-pref orchestration that the per-pref apply() can't express alone.
	if(copy_name)
		var/datum/preference_apply_hook/name_sanitization/name_hook = locate() in GLOB.preference_apply_hooks
		if(name_hook)
			name_hook.apply(character, src)

	var/datum/preference_apply_hook/gender/gender_hook = locate() in GLOB.preference_apply_hooks
	if(gender_hook)
		gender_hook.apply(character, src)

	var/datum/preference_apply_hook/accessories/accessory_hook = locate() in GLOB.preference_apply_hooks
	if(accessory_hook)
		accessory_hook.apply(character, src)

	var/datum/preference_apply_hook/markings/markings_hook = locate() in GLOB.preference_apply_hooks
	if(markings_hook)
		markings_hook.apply(character, src)

	// Protean reconstitutor path — same prosthetic conversion logic the old proc had.
	if(convert_to_prosthetics)
		var/list/pref_organ_data = read_preference(/datum/preference/organ_data)
		var/list/pref_rlimb_data = read_preference(/datum/preference/rlimb_data)
		var/list/organs_to_edit = list()
		for(var/name in list(BP_TORSO, BP_HEAD, BP_GROIN, BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND, BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT))
			var/obj/item/organ/external/O = character.organs_by_name[name]
			if(O)
				var/x = organs_to_edit.Find(O.parent_organ)
				if(x == 0)
					organs_to_edit += name
				else
					organs_to_edit.Insert(x + (O.robotic == ORGAN_NANOFORM ? 1 : 0), name)
		for(var/name in organs_to_edit)
			var/status = pref_organ_data[name]
			var/obj/item/organ/external/O = character.organs_by_name[name]
			if(!O)
				continue
			if(status == "amputated")
				continue
			else if(status == "cyborg")
				O.robotize(pref_rlimb_data[name])
			else
				var/bodytype
				var/_custom_base = read_preference(/datum/preference/text/human/custom_base)
				var/datum/species/selected_species = GLOB.all_species[read_preference(/datum/preference/choiced/species)]
				if(selected_species.selects_bodytype && _custom_base)
					bodytype = _custom_base
				else
					bodytype = selected_species.get_bodytype()
				var/dsi_company = GLOB.dsi_to_species[bodytype] || "DSI - Adaptive"
				O.robotize(dsi_company)

	// Size-trait overlay still needs to run for the vanity case (the trait_synthesis
	// apply_hook is intentionally NOT called here — we don't want produceCopy()).
	character.species?.blood_color = read_preference(/datum/preference/color/human/blood_color)

	var/list/traits_to_copy = list(/datum/trait/neutral/tall,
									/datum/trait/neutral/taller,
									/datum/trait/neutral/tallest,
									/datum/trait/neutral/short,
									/datum/trait/neutral/shorter,
									/datum/trait/neutral/shortest,
									/datum/trait/neutral/obese,
									/datum/trait/neutral/fat,
									/datum/trait/neutral/thin,
									/datum/trait/neutral/thinner,
									/datum/trait/neutral/micro_size_down,
									/datum/trait/neutral/micro_size_up)
	if(character.species)
		character.species.micro_size_mod = 0
		character.species.icon_scale_x = 1
		character.species.icon_scale_y = 1
		for(var/trait in read_preference(/datum/preference/typed_list/traits/neu_traits)) // DQEdit — typed_list pref base
			if(trait in traits_to_copy)
				var/datum/trait/instance = GLOB.all_traits[trait]
				if(!instance)
					continue
				for(var/key, value in instance.var_changes)
					character.species.vars[key] = value
	character.update_transform()

	// Snowflake shapeshifter bodytype derivation — this is what makes vanity_copy_to
	// different from the standard apply pipeline. Resolve the custom_base into the species'
	// vanity_base_fit so the shapeshifter renders the new body without losing the original
	// species datum.
	var/_custom_base = read_preference(/datum/preference/text/human/custom_base)
	var/datum/species/selected_species = GLOB.all_species[read_preference(/datum/preference/choiced/species)]
	var/bodytype_selected
	if(selected_species.selects_bodytype && _custom_base)
		bodytype_selected = _custom_base
	else
		bodytype_selected = selected_species.get_bodytype(character)
	character.dna.base_species = bodytype_selected
	character.species.base_species = bodytype_selected
	character.species.icobase = character.species.get_icobase()
	character.species.deform = character.species.get_icobase(get_deform = TRUE)
	character.species.vanity_base_fit = bodytype_selected
	if(istype(character.species, /datum/species/shapeshifter))
		GLOB.wrapped_species_by_ref["\ref[character]"] = bodytype_selected

	// Finalize: same post-apply work the /datum/preference_apply_hook/finalize hook does.
	for(var/obj/item/clothing/O in character.contents)
		O.handle_digitigrade(character)
	if(character.dna)
		character.dna.ResetUIFrom(character)
	character.force_update_limbs()
	character.regenerate_icons()

	PREF_TRANSACTION_END(src)


// === merged from preferences_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
// DQEdit — metadata_maybes/metadata_favs/matadata_ooc_style were dead declarations
// (never referenced anywhere); equivalent functionality is on /datum/preference/text/living/ooc_notes_{maybes,favs} and /datum/preference/toggle/living/ooc_notes_style. Deleted.
// DQEdit — job_other_low/med/high migrated to /datum/preference/numeric/human/job_other_* subtypes; declarations deleted.
