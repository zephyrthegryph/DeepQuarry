//
// Belly Export Panel
//

/datum/vore_look/export_panel/proc/open_export_panel(mob/user)
	tgui_interact(user)

UI_SCHEMA(vore_belly_export, row(name = schema_text(), desc = schema_text(), display_name = schema_text(), absorbed_desc = nullable(schema_text()), vore_verb = schema_text(), release_verb = schema_text(), prevent_saving = bool(), mode = schema_text(), addons = list_of(schema_text()), item_mode = schema_text(), message_mode = bool(), struggle_messages_outside = list_of(schema_text()), struggle_messages_inside = list_of(schema_text()), absorbed_struggle_messages_outside = list_of(schema_text()), absorbed_struggle_messages_inside = list_of(schema_text()), escape_attempt_messages_owner = list_of(schema_text()), escape_attempt_messages_prey = list_of(schema_text()), escape_messages_owner = list_of(schema_text()), escape_messages_prey = list_of(schema_text()), escape_messages_outside = list_of(schema_text()), escape_item_messages_owner = list_of(schema_text()), escape_item_messages_prey = list_of(schema_text()), escape_item_messages_outside = list_of(schema_text()), escape_fail_messages_owner = list_of(schema_text()), escape_fail_messages_prey = list_of(schema_text()), escape_attempt_absorbed_messages_owner = list_of(schema_text()), escape_attempt_absorbed_messages_prey = list_of(schema_text()), escape_absorbed_messages_owner = list_of(schema_text()), escape_absorbed_messages_prey = list_of(schema_text()), escape_absorbed_messages_outside = list_of(schema_text()), escape_fail_absorbed_messages_owner = list_of(schema_text()), escape_fail_absorbed_messages_prey = list_of(schema_text()), primary_transfer_messages_owner = list_of(schema_text()), primary_transfer_messages_prey = list_of(schema_text()), secondary_transfer_messages_owner = list_of(schema_text()), secondary_transfer_messages_prey = list_of(schema_text()), primary_autotransfer_messages_owner = list_of(schema_text()), primary_autotransfer_messages_prey = list_of(schema_text()), secondary_autotransfer_messages_owner = list_of(schema_text()), secondary_autotransfer_messages_prey = list_of(schema_text()), digest_chance_messages_owner = list_of(schema_text()), digest_chance_messages_prey = list_of(schema_text()), absorb_chance_messages_owner = list_of(schema_text()), absorb_chance_messages_prey = list_of(schema_text()), digest_messages_owner = list_of(schema_text()), digest_messages_prey = list_of(schema_text()), absorb_messages_owner = list_of(schema_text()), absorb_messages_prey = list_of(schema_text()), unabsorb_messages_owner = list_of(schema_text()), unabsorb_messages_prey = list_of(schema_text()), examine_messages = list_of(schema_text()), examine_messages_absorbed = list_of(schema_text()), trash_eater_in = list_of(schema_text()), trash_eater_out = list_of(schema_text()), emotes_digest = list_of(schema_text()), emotes_hold = list_of(schema_text()), emotes_holdabsorbed = list_of(schema_text()), emotes_absorb = list_of(schema_text()), emotes_heal = list_of(schema_text()), emotes_drain = list_of(schema_text()), emotes_steal = list_of(schema_text()), emotes_egg = list_of(schema_text()), emotes_shrink = list_of(schema_text()), emotes_grow = list_of(schema_text()), emotes_unabsorb = list_of(schema_text()), displayed_message_flags = num(), digest_brute = num(), digest_burn = num(), digest_oxy = num(), digest_tox = num(), digest_clone = num(), bellytemperature = num(), temperature_damage = bool(), can_taste = bool(), is_feedable = bool(), contaminates = bool(), contamination_flavor = schema_text(), contamination_color = schema_text(), nutrition_percent = num(), bulge_size = num(), display_absorbed_examine = bool(), save_digest_mode = bool(), emote_active = bool(), emote_time = num(), shrink_grow_size = num(), vorespawn_blacklist = bool(), vorespawn_whitelist = list_of(schema_text()), vorespawn_absorbed = num(), egg_type = schema_text(), egg_name = nullable(schema_text()), egg_size = num(), selective_preference = schema_text(), recycling = bool(), storing_nutrition = bool(), entrance_logs = bool(), item_digest_logs = bool(), eating_privacy_local = schema_text(), private_struggle = bool(), absorbedrename_enabled = bool(), absorbedrename_name = schema_text(), is_wet = bool(), wet_loop = bool(), fancy_vore = bool(), vore_sound = schema_text(), release_sound = schema_text(), sound_volume = num(), noise_freq = num(), affects_vore_sprites = bool(), vore_sprite_flags = list_of(schema_text()), count_absorbed_prey_for_sprite = bool(), absorbed_multiplier = num(), count_liquid_for_sprite = bool(), liquid_multiplier = num(), count_items_for_sprite = bool(), item_multiplier = num(), health_impacts_size = bool(), resist_triggers_animation = bool(), size_factor_for_sprite = num(), belly_sprite_to_affect = schema_text(), undergarment_chosen = schema_text(), undergarment_if_none = nullable(schema_text()), undergarment_color = schema_text(), belly_fullscreen_color = schema_text(), belly_fullscreen_color2 = schema_text(), belly_fullscreen_color3 = schema_text(), belly_fullscreen_color4 = schema_text(), belly_fullscreen_alpha = num(), colorization_enabled = bool(), disable_hud = bool(), belly_fullscreen = schema_text(), escapable = num(), escapechance = num(), escapechance_absorbed = num(), escapetime = num(), belchchance = num(), transferchance = num(), transferlocation = nullable(schema_text()), transferchance_secondary = num(), transferlocation_secondary = nullable(schema_text()), absorbchance = num(), digestchance = num(), autotransferchance = num(), autotransferwait = num(), autotransferlocation = nullable(schema_text()), autotransferextralocation = list_of(schema_text()), autotransfer_enabled = bool(), autotransferchance_secondary = num(), autotransferlocation_secondary = nullable(schema_text()), autotransferextralocation_secondary = list_of(schema_text()), autotransfer_min_amount = num(), autotransfer_max_amount = num(), autotransfer_whitelist = list_of(schema_text()), autotransfer_blacklist = list_of(schema_text()), autotransfer_whitelist_items = list_of(schema_text()), autotransfer_blacklist_items = list_of(schema_text()), autotransfer_secondary_whitelist = list_of(schema_text()), autotransfer_secondary_blacklist = list_of(schema_text()), autotransfer_secondary_whitelist_items = list_of(schema_text()), autotransfer_secondary_blacklist_items = list_of(schema_text()), show_liquids = bool(), reagentbellymode = bool(), reagent_gen_cost_limit = num(), reagent_chosen = schema_text(), reagent_name = schema_text(), reagent_transfer_verb = schema_text(), gen_time_display = schema_text(), custom_max_volume = num(), vorefootsteps_sounds = bool(), liquid_overlay = bool(), max_liquid_level = num(), reagent_touches = bool(), mush_overlay = bool(), mush_color = schema_text(), mush_alpha = num(), max_mush = num(), min_mush = num(), item_mush_val = num(), custom_reagentcolor = nullable(schema_text()), custom_reagentalpha = num(), metabolism_overlay = bool(), metabolism_mush_ratio = num(), max_ingested = num(), custom_ingested_color = nullable(schema_text()), custom_ingested_alpha = num(), reagent_mode_flag_list = list_of(schema_text()), show_fullness_messages = bool(), liquid_fullness1_messages = bool(), liquid_fullness2_messages = bool(), liquid_fullness3_messages = bool(), liquid_fullness4_messages = bool(), liquid_fullness5_messages = bool(), fullness1_messages = list_of(schema_text()), fullness2_messages = list_of(schema_text()), fullness3_messages = list_of(schema_text()), fullness4_messages = list_of(schema_text()), fullness5_messages = list_of(schema_text())))

UI_SCHEMA(vore_soulcatcher_export, row(name = schema_text(), setting_flags = num(), inside_flavor = schema_text(), capture_message = schema_text(), transit_message = schema_text(), release_message = schema_text(), transfer_message = schema_text(), delete_message = schema_text(), linked_belly = nullable(schema_text())))

CAPABILITIES(/datum/vore_look/export_panel)
	interface("VorePanelExport", title = "Vore Export Panel")
	ui_shape(db_version = schema_text(), db_repo = schema_text(), mob_name = nullable(schema_text()), bellies = list_of(vore_belly_export()), soulcatcher = nullable(vore_soulcatcher_export()))

/// The export window shows none of the vore panel's static data (its words, name limits): it only reads what ui_data() hands it.
/datum/vore_look/export_panel/ui_static_data(datum/act/eval/A)
	return list()

/// /datum/vore_look/export_panel's window data.
/datum/vore_look/export_panel/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	var/mob/living/host = user

	data["db_version"] = "0.3"
	data["db_repo"] = "chompstation"
	data["mob_name"] = host.read_preference(/datum/preference/name/real_name)
	data["bellies"] = list()
	data["soulcatcher"] = null

	for(var/belly in host.vore_organs)
		if(isbelly(belly))
			var/obj/belly/B = belly
			var/belly_data = list()

			// General Information
			belly_data["name"] = B.name
			belly_data["desc"] = B.desc
			belly_data["display_name"] = B.display_name
			belly_data["absorbed_desc"] = B.absorbed_desc
			belly_data["vore_verb"] = B.vore_verb
			belly_data["release_verb"] = B.release_verb
			belly_data["prevent_saving"] = B.prevent_saving

			// Controls
			belly_data["mode"] = B.digest_mode
			var/list/addons = list()
			for(var/flag_name in B.mode_flag_list)
				if(B.mode_flags & B.mode_flag_list[flag_name])
					addons.Add(flag_name)
			belly_data["addons"] = addons
			belly_data["item_mode"] = B.item_digest_mode
			belly_data["message_mode"] = B.message_mode

			// Messages
			belly_data["struggle_messages_outside"] = list()
			for(var/msg in B.struggle_messages_outside)
				belly_data["struggle_messages_outside"] += msg

			belly_data["struggle_messages_inside"] = list()
			for(var/msg in B.struggle_messages_inside)
				belly_data["struggle_messages_inside"] += msg

			belly_data["absorbed_struggle_messages_outside"] = list()
			for(var/msg in B.absorbed_struggle_messages_outside)
				belly_data["absorbed_struggle_messages_outside"] += msg

			belly_data["absorbed_struggle_messages_inside"] = list()
			for(var/msg in B.absorbed_struggle_messages_inside)
				belly_data["absorbed_struggle_messages_inside"] += msg

			belly_data["escape_attempt_messages_owner"] = list()
			for(var/msg in B.escape_attempt_messages_owner)
				belly_data["escape_attempt_messages_owner"] += msg

			belly_data["escape_attempt_messages_prey"] = list()
			for(var/msg in B.escape_attempt_messages_prey)
				belly_data["escape_attempt_messages_prey"] += msg

			belly_data["escape_messages_owner"] = list()
			for(var/msg in B.escape_messages_owner)
				belly_data["escape_messages_owner"] += msg

			belly_data["escape_messages_prey"] = list()
			for(var/msg in B.escape_messages_prey)
				belly_data["escape_messages_prey"] += msg

			belly_data["escape_messages_outside"] = list()
			for(var/msg in B.escape_messages_outside)
				belly_data["escape_messages_outside"] += msg

			belly_data["escape_item_messages_owner"] = list()
			for(var/msg in B.escape_item_messages_owner)
				belly_data["escape_item_messages_owner"] += msg

			belly_data["escape_item_messages_prey"] = list()
			for(var/msg in B.escape_item_messages_prey)
				belly_data["escape_item_messages_prey"] += msg

			belly_data["escape_item_messages_outside"] = list()
			for(var/msg in B.escape_item_messages_outside)
				belly_data["escape_item_messages_outside"] += msg

			belly_data["escape_fail_messages_owner"] = list()
			for(var/msg in B.escape_fail_messages_owner)
				belly_data["escape_fail_messages_owner"] += msg

			belly_data["escape_fail_messages_prey"] = list()
			for(var/msg in B.escape_fail_messages_prey)
				belly_data["escape_fail_messages_prey"] += msg

			belly_data["escape_attempt_absorbed_messages_owner"] = list()
			for(var/msg in B.escape_attempt_absorbed_messages_owner)
				belly_data["escape_attempt_absorbed_messages_owner"] += msg

			belly_data["escape_attempt_absorbed_messages_prey"] = list()
			for(var/msg in B.escape_attempt_absorbed_messages_prey)
				belly_data["escape_attempt_absorbed_messages_prey"] += msg

			belly_data["escape_absorbed_messages_owner"] = list()
			for(var/msg in B.escape_absorbed_messages_owner)
				belly_data["escape_absorbed_messages_owner"] += msg

			belly_data["escape_absorbed_messages_prey"] = list()
			for(var/msg in B.escape_absorbed_messages_prey)
				belly_data["escape_absorbed_messages_prey"] += msg

			belly_data["escape_absorbed_messages_outside"] = list()
			for(var/msg in B.escape_absorbed_messages_outside)
				belly_data["escape_absorbed_messages_outside"] += msg

			belly_data["escape_fail_absorbed_messages_owner"] = list()
			for(var/msg in B.escape_fail_absorbed_messages_owner)
				belly_data["escape_fail_absorbed_messages_owner"] += msg

			belly_data["escape_fail_absorbed_messages_prey"] = list()
			for(var/msg in B.escape_fail_absorbed_messages_prey)
				belly_data["escape_fail_absorbed_messages_prey"] += msg

			belly_data["primary_transfer_messages_owner"] = list()
			for(var/msg in B.primary_transfer_messages_owner)
				belly_data["primary_transfer_messages_owner"] += msg

			belly_data["primary_transfer_messages_prey"] = list()
			for(var/msg in B.primary_transfer_messages_prey)
				belly_data["primary_transfer_messages_prey"] += msg

			belly_data["secondary_transfer_messages_owner"] = list()
			for(var/msg in B.secondary_transfer_messages_owner)
				belly_data["secondary_transfer_messages_owner"] += msg

			belly_data["secondary_transfer_messages_prey"] = list()
			for(var/msg in B.secondary_transfer_messages_prey)
				belly_data["secondary_transfer_messages_prey"] += msg

			belly_data["primary_autotransfer_messages_owner"] = list()
			for(var/msg in B.primary_autotransfer_messages_owner)
				belly_data["primary_autotransfer_messages_owner"] += msg

			belly_data["primary_autotransfer_messages_prey"] = list()
			for(var/msg in B.primary_autotransfer_messages_prey)
				belly_data["primary_autotransfer_messages_prey"] += msg

			belly_data["secondary_autotransfer_messages_owner"] = list()
			for(var/msg in B.secondary_autotransfer_messages_owner)
				belly_data["secondary_autotransfer_messages_owner"] += msg

			belly_data["secondary_autotransfer_messages_prey"] = list()
			for(var/msg in B.secondary_autotransfer_messages_prey)
				belly_data["secondary_autotransfer_messages_prey"] += msg

			belly_data["digest_chance_messages_owner"] = list()
			for(var/msg in B.digest_chance_messages_owner)
				belly_data["digest_chance_messages_owner"] += msg

			belly_data["digest_chance_messages_prey"] = list()
			for(var/msg in B.digest_chance_messages_prey)
				belly_data["digest_chance_messages_prey"] += msg

			belly_data["absorb_chance_messages_owner"] = list()
			for(var/msg in B.absorb_chance_messages_owner)
				belly_data["absorb_chance_messages_owner"] += msg

			belly_data["absorb_chance_messages_prey"] = list()
			for(var/msg in B.absorb_chance_messages_prey)
				belly_data["absorb_chance_messages_prey"] += msg

			belly_data["digest_messages_owner"] = list()
			for(var/msg in B.digest_messages_owner)
				belly_data["digest_messages_owner"] += msg

			belly_data["digest_messages_prey"] = list()
			for(var/msg in B.digest_messages_prey)
				belly_data["digest_messages_prey"] += msg

			belly_data["absorb_messages_owner"] = list()
			for(var/msg in B.absorb_messages_owner)
				belly_data["absorb_messages_owner"] += msg

			belly_data["absorb_messages_prey"] = list()
			for(var/msg in B.absorb_messages_prey)
				belly_data["absorb_messages_prey"] += msg

			belly_data["unabsorb_messages_owner"] = list()
			for(var/msg in B.unabsorb_messages_owner)
				belly_data["unabsorb_messages_owner"] += msg

			belly_data["unabsorb_messages_prey"] = list()
			for(var/msg in B.unabsorb_messages_prey)
				belly_data["unabsorb_messages_prey"] += msg

			belly_data["examine_messages"] = list()
			for(var/msg in B.examine_messages)
				belly_data["examine_messages"] += msg

			belly_data["examine_messages_absorbed"] = list()
			for(var/msg in B.examine_messages_absorbed)
				belly_data["examine_messages_absorbed"] += msg

			belly_data["trash_eater_in"] = list()
			for(var/msg in B.trash_eater_in)
				belly_data["trash_eater_in"] += msg

			belly_data["trash_eater_out"] = list()
			for(var/msg in B.trash_eater_out)
				belly_data["trash_eater_out"] += msg

			// I will use this first before the code above gets fixed
			belly_data["emotes_digest"] = list()
			for(var/msg in B.emote_lists[DM_DIGEST])
				belly_data["emotes_digest"] += msg

			belly_data["emotes_hold"] = list()
			for(var/msg in B.emote_lists[DM_HOLD])
				belly_data["emotes_hold"] += msg

			belly_data["emotes_holdabsorbed"] = list()
			for(var/msg in B.emote_lists[DM_HOLD_ABSORBED])
				belly_data["emotes_holdabsorbed"] += msg

			belly_data["emotes_absorb"] = list()
			for(var/msg in B.emote_lists[DM_ABSORB])
				belly_data["emotes_absorb"] += msg

			belly_data["emotes_heal"] = list()
			for(var/msg in B.emote_lists[DM_HEAL])
				belly_data["emotes_heal"] += msg

			belly_data["emotes_drain"] = list()
			for(var/msg in B.emote_lists[DM_DRAIN])
				belly_data["emotes_drain"] += msg

			belly_data["emotes_steal"] = list()
			for(var/msg in B.emote_lists[DM_SIZE_STEAL])
				belly_data["emotes_steal"] += msg

			belly_data["emotes_egg"] = list()
			for(var/msg in B.emote_lists[DM_EGG])
				belly_data["emotes_egg"] += msg

			belly_data["emotes_shrink"] = list()
			for(var/msg in B.emote_lists[DM_SHRINK])
				belly_data["emotes_shrink"] += msg

			belly_data["emotes_grow"] = list()
			for(var/msg in B.emote_lists[DM_GROW])
				belly_data["emotes_grow"] += msg

			belly_data["emotes_unabsorb"] = list()
			for(var/msg in B.emote_lists[DM_UNABSORB])
				belly_data["emotes_unabsorb"] += msg

			belly_data["displayed_message_flags"] = B.displayed_message_flags

			// Options
			belly_data["digest_brute"] = B.digest_brute
			belly_data["digest_burn"] = B.digest_burn
			belly_data["digest_oxy"] = B.digest_oxy
			belly_data["digest_tox"] = B.digest_tox
			belly_data["digest_clone"] = B.digest_clone

			belly_data["bellytemperature"] = B.bellytemperature
			belly_data["temperature_damage"] = B.temperature_damage

			belly_data["can_taste"] = B.can_taste
			belly_data["is_feedable"] = B.is_feedable
			belly_data["contaminates"] = B.contaminates
			belly_data["contamination_flavor"] = B.contamination_flavor
			belly_data["contamination_color"] = B.contamination_color
			belly_data["nutrition_percent"] = B.nutrition_percent
			belly_data["bulge_size"] = B.bulge_size
			belly_data["display_absorbed_examine"] = B.display_absorbed_examine
			belly_data["save_digest_mode"] = B.save_digest_mode
			belly_data["emote_active"] = B.emote_active
			belly_data["emote_time"] = B.emote_time
			belly_data["shrink_grow_size"] = B.shrink_grow_size
			belly_data["vorespawn_blacklist"] = B.vorespawn_blacklist
			belly_data["vorespawn_whitelist"] = B.vorespawn_whitelist
			belly_data["vorespawn_absorbed"] = B.vorespawn_absorbed
			belly_data["egg_type"] = B.egg_type
			belly_data["egg_name"] = B.egg_name
			belly_data["egg_size"] = B.egg_size
			belly_data["selective_preference"] = B.selective_preference
			belly_data["recycling"] = B.recycling
			belly_data["storing_nutrition"] = B.storing_nutrition
			belly_data["entrance_logs"] = B.entrance_logs
			belly_data["item_digest_logs"] = B.item_digest_logs
			belly_data["eating_privacy_local"] = B.eating_privacy_local
			belly_data["private_struggle"] = B.private_struggle
			belly_data["absorbedrename_enabled"] = B.absorbedrename_enabled
			belly_data["absorbedrename_name"] = B.absorbedrename_name

			// Sounds
			belly_data["is_wet"] = B.is_wet
			belly_data["wet_loop"] = B.wet_loop
			belly_data["fancy_vore"] = B.fancy_vore
			belly_data["vore_sound"] = B.vore_sound
			belly_data["release_sound"] = B.release_sound
			belly_data["sound_volume"] = B.sound_volume
			belly_data["noise_freq"] = B.noise_freq

			// Visuals
			belly_data["affects_vore_sprites"] = B.affects_vore_sprites
			var/list/sprite_flags = list()
			for(var/flag_name in B.vore_sprite_flag_list)
				if(B.vore_sprite_flags & B.vore_sprite_flag_list[flag_name])
					sprite_flags.Add(flag_name)
			belly_data["vore_sprite_flags"] = sprite_flags
			belly_data["count_absorbed_prey_for_sprite"] = B.count_absorbed_prey_for_sprite
			belly_data["absorbed_multiplier"] = B.absorbed_multiplier
			belly_data["count_liquid_for_sprite"] = B.count_liquid_for_sprite
			belly_data["liquid_multiplier"] = B.liquid_multiplier
			belly_data["count_items_for_sprite"] = B.count_items_for_sprite
			belly_data["item_multiplier"] = B.item_multiplier
			belly_data["health_impacts_size"] = B.health_impacts_size
			belly_data["resist_triggers_animation"] = B.resist_triggers_animation
			belly_data["size_factor_for_sprite"] = B.size_factor_for_sprite
			belly_data["belly_sprite_to_affect"] = B.belly_sprite_to_affect
			belly_data["undergarment_chosen"] = B.undergarment_chosen
			belly_data["undergarment_if_none"] = B.undergarment_if_none
			belly_data["undergarment_color"] = B.undergarment_color

			// Visuals (Belly Fullscreens Preview and Coloring)
			belly_data["belly_fullscreen_color"] = B.belly_fullscreen_color
			belly_data["belly_fullscreen_color2"] = B.belly_fullscreen_color2
			belly_data["belly_fullscreen_color3"] = B.belly_fullscreen_color3
			belly_data["belly_fullscreen_color4"] = B.belly_fullscreen_color4
			belly_data["belly_fullscreen_alpha"] = B.belly_fullscreen_alpha
			belly_data["colorization_enabled"] = B.colorization_enabled

			// Visuals (Vore FX)
			belly_data["disable_hud"] = B.disable_hud
			belly_data["belly_fullscreen"] = B.belly_fullscreen

			// Interactions
			belly_data["escapable"] = B.escapable

			belly_data["escapechance"] = B.escapechance
			belly_data["escapechance_absorbed"] = B.escapechance_absorbed
			belly_data["escapetime"] = B.escapetime/10

			belly_data["belchchance"] = B.belchchance

			belly_data["transferchance"] = B.transferchance
			belly_data["transferlocation"] = B.transferlocation

			belly_data["transferchance_secondary"] = B.transferchance_secondary
			belly_data["transferlocation_secondary"] = B.transferlocation_secondary

			belly_data["absorbchance"] = B.absorbchance
			belly_data["digestchance"] = B.digestchance

			// Interactions (Auto-Transfer)
			belly_data["autotransferchance"] = B.autotransferchance
			belly_data["autotransferwait"] = B.autotransferwait/10
			belly_data["autotransferlocation"] = B.autotransferlocation
			belly_data["autotransferextralocation"] = (B.autotransferextralocation || list())
			belly_data["autotransfer_enabled"] = B.autotransfer_enabled
			belly_data["autotransferchance_secondary"] = B.autotransferchance_secondary
			belly_data["autotransferlocation_secondary"] = B.autotransferlocation_secondary
			belly_data["autotransferextralocation_secondary"] = (B.autotransferextralocation_secondary || list())
			belly_data["autotransfer_min_amount"] = B.autotransfer_min_amount
			belly_data["autotransfer_max_amount"] = B.autotransfer_max_amount
			var/list/at_whitelist = list()
			for(var/flag_name in B.autotransfer_flags_list)
				if(B.autotransfer_whitelist & B.autotransfer_flags_list[flag_name])
					at_whitelist.Add(flag_name)
			belly_data["autotransfer_whitelist"] = at_whitelist
			var/list/at_blacklist = list()
			for(var/flag_name in B.autotransfer_flags_list)
				if(B.autotransfer_blacklist & B.autotransfer_flags_list[flag_name])
					at_blacklist.Add(flag_name)
			belly_data["autotransfer_blacklist"] = at_blacklist
			var/list/at_whitelist_items = list()
			for(var/flag_name in B.autotransfer_flags_list_items)
				if(B.autotransfer_whitelist_items & B.autotransfer_flags_list_items[flag_name])
					at_whitelist_items.Add(flag_name)
			belly_data["autotransfer_whitelist_items"] = at_whitelist_items
			var/list/at_blacklist_items = list()
			for(var/flag_name in B.autotransfer_flags_list_items)
				if(B.autotransfer_blacklist_items & B.autotransfer_flags_list_items[flag_name])
					at_blacklist_items.Add(flag_name)
			belly_data["autotransfer_blacklist_items"] = at_blacklist_items
			var/list/at_secondary_whitelist = list()
			for(var/flag_name in B.autotransfer_flags_list)
				if(B.autotransfer_secondary_whitelist & B.autotransfer_flags_list[flag_name])
					at_secondary_whitelist.Add(flag_name)
			belly_data["autotransfer_secondary_whitelist"] = at_secondary_whitelist
			var/list/at_secondary_blacklist = list()
			for(var/flag_name in B.autotransfer_flags_list)
				if(B.autotransfer_secondary_blacklist & B.autotransfer_flags_list[flag_name])
					at_secondary_blacklist.Add(flag_name)
			belly_data["autotransfer_secondary_blacklist"] = at_secondary_blacklist
			var/list/at_secondary_whitelist_items = list()
			for(var/flag_name in B.autotransfer_flags_list_items)
				if(B.autotransfer_secondary_whitelist_items & B.autotransfer_flags_list_items[flag_name])
					at_secondary_whitelist_items.Add(flag_name)
			belly_data["autotransfer_secondary_whitelist_items"] = at_secondary_whitelist_items
			var/list/at_secondary_blacklist_items = list()
			for(var/flag_name in B.autotransfer_flags_list_items)
				if(B.autotransfer_secondary_blacklist_items & B.autotransfer_flags_list_items[flag_name])
					at_secondary_blacklist_items.Add(flag_name)
			belly_data["autotransfer_secondary_blacklist_items"] = at_secondary_blacklist_items

			// Liquid Options
			belly_data["show_liquids"] = B.show_liquids
			belly_data["reagentbellymode"] = B.reagentbellymode
			belly_data["reagent_gen_cost_limit"] = B.reagent_gen_cost_limit
			belly_data["reagent_chosen"] = B.reagent_chosen
			belly_data["reagent_name"] = B.reagent_name
			belly_data["reagent_transfer_verb"] = B.reagent_transfer_verb
			belly_data["gen_time_display"] = B.gen_time_display
			belly_data["custom_max_volume"] = B.custom_max_volume
			belly_data["vorefootsteps_sounds"] = B.vorefootsteps_sounds
			belly_data["liquid_overlay"] = B.liquid_overlay
			belly_data["max_liquid_level"] = B.max_liquid_level
			belly_data["reagent_touches"] = B.reagent_touches
			belly_data["mush_overlay"] = B.mush_overlay
			belly_data["mush_color"] = B.mush_color
			belly_data["mush_alpha"] = B.mush_alpha
			belly_data["max_mush"] = B.max_mush
			belly_data["min_mush"] = B.min_mush
			belly_data["item_mush_val"] = B.item_mush_val
			belly_data["custom_reagentcolor"] = B.custom_reagentcolor
			belly_data["custom_reagentalpha"] = B.custom_reagentalpha
			belly_data["metabolism_overlay"] = B.metabolism_overlay
			belly_data["metabolism_mush_ratio"] = B.metabolism_mush_ratio
			belly_data["max_ingested"] = B.max_ingested
			belly_data["custom_ingested_color"] = B.custom_ingested_color
			belly_data["custom_ingested_alpha"] = B.custom_ingested_alpha

			var/list/reagent_flags = list()
			for(var/flag_name in B.reagent_mode_flag_list)
				if(B.reagent_mode_flags & B.reagent_mode_flag_list[flag_name])
					reagent_flags.Add(flag_name)
			belly_data["reagent_mode_flag_list"] = reagent_flags

			data["bellies"] += list(belly_data)

			// Liquid Messages
			belly_data["show_fullness_messages"] = B.show_fullness_messages
			belly_data["liquid_fullness1_messages"] = B.liquid_fullness1_messages
			belly_data["liquid_fullness2_messages"] = B.liquid_fullness2_messages
			belly_data["liquid_fullness3_messages"] = B.liquid_fullness3_messages
			belly_data["liquid_fullness4_messages"] = B.liquid_fullness4_messages
			belly_data["liquid_fullness5_messages"] = B.liquid_fullness5_messages

			belly_data["fullness1_messages"] = list()
			for(var/msg in B.fullness1_messages)
				belly_data["fullness1_messages"] += msg

			belly_data["fullness2_messages"] = list()
			for(var/msg in B.fullness2_messages)
				belly_data["fullness2_messages"] += msg

			belly_data["fullness3_messages"] = list()
			for(var/msg in B.fullness3_messages)
				belly_data["fullness3_messages"] += msg

			belly_data["fullness4_messages"] = list()
			for(var/msg in B.fullness4_messages)
				belly_data["fullness4_messages"] += msg

			belly_data["fullness5_messages"] = list()
			for(var/msg in B.fullness5_messages)
				belly_data["fullness5_messages"] += msg

	// Soulcatcher export
	if(user.soulgem)
		var/obj/soulgem/gem = user.soulgem
		var/list/soulcatcher_data = list()
		soulcatcher_data["name"] = gem.name
		soulcatcher_data["setting_flags"] = gem.setting_flags
		soulcatcher_data["inside_flavor"] = gem.inside_flavor
		soulcatcher_data["capture_message"] = gem.capture_message
		soulcatcher_data["transit_message"] = gem.transit_message
		soulcatcher_data["release_message"] = gem.release_message
		soulcatcher_data["transfer_message"] = gem.transfer_message
		soulcatcher_data["delete_message"] = gem.delete_message
		soulcatcher_data["linked_belly"] = gem.linked_belly()

		data["soulcatcher"] = soulcatcher_data

	return data
