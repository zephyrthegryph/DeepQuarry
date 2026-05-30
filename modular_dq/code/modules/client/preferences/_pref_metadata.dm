// DQAdd — Category/group/widget metadata for prefs whose declarations live in third-party
// (Bay/CHOMP/TG) files we don't want to touch directly. Runs once at world init: walks
// the table and writes the metadata onto the static vars of the existing pref singletons.
//
// NEW PREFS SHOULD SET category/group/widget DIRECTLY on their subtype declaration in
// their own file. This table is the fallback for inherited prefs only — anything declared
// in modular_dq's own pref files should not appear here.
//
// CATEGORY LAYOUT (consolidated for a clean character setup UI):
//   identity   — Name, Demographics, Gender, Species, Spawn, Background, Records, OOC notes,
//                 Speech verbs, Language (everything personal/biographical about the char)
//   appearance — Body, Hair, Ears, Tail, Wings, Blood, Markings, Organs, Preview
//   size_voice — Size sliders + voice/sound prefs
//   loadout    — Starting Kit + Underwear + Gear builder
//   occupation — Job priorities
//   traits     — Trait picker
//   antag      — Antag opt-ins, antag faction, visibility, etc.
//   vore       — Vore basics, directory, thermal messages
//   game       — Persistence, NIF, PAI char config (niche / collapsed)

// Init runs after GLOB.preference_entries has been populated.
GLOBAL_LIST_INIT(pref_metadata_table, init_pref_metadata_table())

/proc/init_pref_metadata_table()
	. = list()

	//// IDENTITY ////
	// Name + flags
	tag_pref(., /datum/preference/name/real_name, "identity", "name")
	tag_pref(., /datum/preference/name/nickname, "identity", "name")
	tag_pref(., /datum/preference/toggle/human/name_is_always_random, "identity", "name")
	// Gender
	tag_pref(., /datum/preference/choiced/gender/biological, "identity", "gender")
	tag_pref(., /datum/preference/choiced/gender/identifying, "identity", "gender")
	// Demographics (age + bday_announce). bday_month/day live in the Birthday editor.
	tag_pref(., /datum/preference/numeric/human/age, "identity", "demographics")
	tag_pref(., /datum/preference/toggle/human/bday_announce, "identity", "demographics")
	// Species
	tag_pref(., /datum/preference/choiced/species, "identity", "species")
	tag_pref(., /datum/preference/text/human/custom_species, "identity", "species")
	tag_pref(., /datum/preference/text/human/custom_base, "identity", "species")
	// Spawn point
	tag_pref(., /datum/preference/choiced/living/spawnpoint, "identity", "spawn")
	// Background (formerly its own tab)
	tag_pref(., /datum/preference/text/human/birthplace, "identity", "background")
	tag_pref(., /datum/preference/text/human/citizenship, "identity", "background")
	tag_pref(., /datum/preference/text/human/faction, "identity", "background")
	tag_pref(., /datum/preference/text/human/home_system, "identity", "background")
	tag_pref(., /datum/preference/text/human/religion, "identity", "background")
	tag_pref(., /datum/preference/choiced/human/economic_status, "identity", "background")
	// Speech verbs
	tag_pref(., /datum/preference/text/human/custom_say, "identity", "speech_verbs")
	tag_pref(., /datum/preference/text/human/custom_whisper, "identity", "speech_verbs")
	tag_pref(., /datum/preference/text/human/custom_ask, "identity", "speech_verbs")
	tag_pref(., /datum/preference/text/human/custom_exclaim, "identity", "speech_verbs")
	// Language (formerly its own tab)
	tag_pref(., /datum/preference/numeric/human/extra_languages, "identity", "language")
	tag_pref(., /datum/preference/text/human/preferred_language, "identity", "language")
	tag_pref(., /datum/preference/color/human/runechat_color, "identity", "language")
	tag_pref(., /datum/preference/alternate_languages, "identity", "language", PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/language_prefixes, "identity", "language", PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/language_custom_keys, "identity", "language", PREF_WIDGET_HIDDEN)
	// Flavor / custom link
	tag_pref(., /datum/preference/text/human/custom_link, "identity", "flavor")
	tag_pref(., /datum/preference/flavor_texts, "identity", "flavor", PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/flavour_texts_robot, "identity", "flavor", PREF_WIDGET_HIDDEN)
	// Records (collapsible — long-form text)
	tag_pref(., /datum/preference/text/human/med_record, "identity", "records", PREF_WIDGET_LONGTEXT)
	tag_pref(., /datum/preference/text/human/sec_record, "identity", "records", PREF_WIDGET_LONGTEXT)
	tag_pref(., /datum/preference/text/human/gen_record, "identity", "records", PREF_WIDGET_LONGTEXT)
	// OOC notes family (collapsible — multi-textarea wall)
	tag_pref(., /datum/preference/text/living/ooc_notes, "identity", "ooc_notes", PREF_WIDGET_LONGTEXT)
	tag_pref(., /datum/preference/text/living/ooc_notes_likes, "identity", "ooc_notes", PREF_WIDGET_LONGTEXT)
	tag_pref(., /datum/preference/text/living/ooc_notes_dislikes, "identity", "ooc_notes", PREF_WIDGET_LONGTEXT)
	tag_pref(., /datum/preference/text/living/ooc_notes_favs, "identity", "ooc_notes", PREF_WIDGET_LONGTEXT)
	tag_pref(., /datum/preference/text/living/ooc_notes_maybes, "identity", "ooc_notes", PREF_WIDGET_LONGTEXT)
	tag_pref(., /datum/preference/text/living/private_notes, "identity", "ooc_notes", PREF_WIDGET_LONGTEXT)
	tag_pref(., /datum/preference/toggle/living/ooc_notes_style, "identity", "ooc_notes")

	//// APPEARANCE ////
	// Body
	tag_pref(., /datum/preference/numeric/human/s_tone, "appearance", "body")
	tag_pref(., /datum/preference/color/human/skin_color, "appearance", "body")
	tag_pref(., /datum/preference/color/human/eyes_color, "appearance", "body")
	tag_pref(., /datum/preference/toggle/human/synth_color, "appearance", "body")
	tag_pref(., /datum/preference/toggle/human/synth_markings, "appearance", "body")
	tag_pref(., /datum/preference/color/human/synth_color, "appearance", "body")
	tag_pref(., /datum/preference/toggle/human/digitigrade, "appearance", "body")
	// Blood
	tag_pref(., /datum/preference/text/human/b_type, "appearance", "blood")
	tag_pref(., /datum/preference/text/human/blood_reagents, "appearance", "blood")
	tag_pref(., /datum/preference/color/human/blood_color, "appearance", "blood")
	// Hair
	tag_pref(., /datum/preference/text/human/h_style, "appearance", "hair")
	tag_pref(., /datum/preference/text/human/f_style, "appearance", "hair")
	tag_pref(., /datum/preference/text/human/grad_style, "appearance", "hair")
	tag_pref(., /datum/preference/color/human/hair_color, "appearance", "hair")
	tag_pref(., /datum/preference/color/human/facial_color, "appearance", "hair")
	tag_pref(., /datum/preference/color/human/grad_color, "appearance", "hair")
	// Ears
	tag_pref(., /datum/preference/text/human/ear_style, "appearance", "ears")
	tag_pref(., /datum/preference/text/human/ear_secondary_style, "appearance", "ears")
	tag_pref(., /datum/preference/color/human/ears_color1, "appearance", "ears")
	tag_pref(., /datum/preference/color/human/ears_color2, "appearance", "ears")
	tag_pref(., /datum/preference/color/human/ears_color3, "appearance", "ears")
	tag_pref(., /datum/preference/numeric/human/ears_alpha, "appearance", "ears")
	tag_pref(., /datum/preference/numeric/human/ears_alpha/secondary, "appearance", "ears")
	tag_pref(., /datum/preference/ear_secondary_colors, "appearance", "ears", PREF_WIDGET_HIDDEN)
	// Tail
	tag_pref(., /datum/preference/text/human/tail_style, "appearance", "tail")
	tag_pref(., /datum/preference/color/human/tail_color1, "appearance", "tail")
	tag_pref(., /datum/preference/color/human/tail_color2, "appearance", "tail")
	tag_pref(., /datum/preference/color/human/tail_color3, "appearance", "tail")
	tag_pref(., /datum/preference/numeric/human/tail_alpha, "appearance", "tail")
	tag_pref(., /datum/preference/choiced/human/tail_layering, "appearance", "tail")
	// Wings
	tag_pref(., /datum/preference/text/human/wing_style, "appearance", "wings")
	tag_pref(., /datum/preference/color/human/wing_color1, "appearance", "wings")
	tag_pref(., /datum/preference/color/human/wing_color2, "appearance", "wings")
	tag_pref(., /datum/preference/color/human/wing_color3, "appearance", "wings")
	tag_pref(., /datum/preference/numeric/human/wing_alpha, "appearance", "wings")
	// Markings (handled by editor)
	tag_pref(., /datum/preference/body_markings, "appearance", "markings", PREF_WIDGET_HIDDEN)
	// Preview controls
	tag_pref(., /datum/preference/numeric/human/equip_preview_mob, "appearance", "preview", PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/toggle/human/preview_loadout, "appearance", "preview")
	tag_pref(., /datum/preference/toggle/human/preview_job, "appearance", "preview")
	tag_pref(., /datum/preference/toggle/human/animations_toggle, "appearance", "preview")

	//// SIZE & VOICE ////
	tag_pref(., /datum/preference/numeric/human/size_multiplier, "size_voice", "size")
	tag_pref(., /datum/preference/numeric/human/weight_vr, "size_voice", "size")
	tag_pref(., /datum/preference/numeric/human/weight_gain, "size_voice", "size")
	tag_pref(., /datum/preference/numeric/human/weight_loss, "size_voice", "size")
	tag_pref(., /datum/preference/toggle/human/fuzzy, "size_voice", "size")
	tag_pref(., /datum/preference/toggle/human/offset_override, "size_voice", "size")
	tag_pref(., /datum/preference/numeric/human/voice_freq, "size_voice", "voice")
	tag_pref(., /datum/preference/text/human/voice_sound, "size_voice", "voice")
	tag_pref(., /datum/preference/text/human/custom_speech_bubble, "size_voice", "voice")
	tag_pref(., /datum/preference/text/human/custom_footstep, "size_voice", "voice")
	tag_pref(., /datum/preference/text/human/species_sound, "size_voice", "voice")

	//// LOADOUT ////
	// DQEdit — headset/backbag/pdachoice prefs deleted; their variants are loadout gear
	// datums now. Remaining starting-kit prefs (no_jacket toggle, ringtone, comm visibility)
	// stay hidden and surface via the starting_kit editor or the loadout panel.
	tag_pref(., /datum/preference/text/human/ringtone, "loadout", "starting_kit", PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/toggle/human/communicator_visibility, "loadout", "starting_kit", PREF_WIDGET_HIDDEN)
	// Composite (editors)
	tag_pref(., /datum/preference/all_underwear, "loadout", "underwear", PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/all_underwear_metadata, "loadout", null, PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/gear_list, "loadout", "gear", PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/text/human/gear_slot, "loadout", "gear", PREF_WIDGET_HIDDEN)

	//// OCCUPATION ////
	// Single sparse assoc pref; the per-bucket bitfields are gone.
	tag_pref(., /datum/preference/job_priorities, "occupation", null, PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/toggle/human/prefer_visitor_role, "occupation", null, PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/player_alt_titles, "occupation", null, PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/numeric/human/alternate_option, "occupation", null, PREF_WIDGET_HIDDEN)

	//// TRAITS ////
	tag_pref(., /datum/preference/typed_list/traits/pos_traits, "traits", null, PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/typed_list/traits/neu_traits, "traits", null, PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/typed_list/traits/neg_traits, "traits", null, PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/numeric/human/starting_trait_points, "traits", null, PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/numeric/human/max_traits, "traits", null, PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/numeric/human/traits_cheating, "traits", null, PREF_WIDGET_HIDDEN)

	//// MIND/BODY ////
	tag_pref(., /datum/preference/numeric/body_points_spent, "mind_body", null, PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/typed_list/body_perks, "mind_body", null, PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/typed_list/mind_perks, "mind_body", null, PREF_WIDGET_HIDDEN)

	//// ANTAG ////
	tag_pref(., /datum/preference/numeric/human/be_special, "antag", null, PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/text/human/antag_faction, "antag")
	tag_pref(., /datum/preference/choiced/human/antag_vis, "antag")
	tag_pref(., /datum/preference/text/human/exploit_record, "antag", null, PREF_WIDGET_LONGTEXT)
	tag_pref(., /datum/preference/toggle/human/vantag_volunteer, "antag")
	tag_pref(., /datum/preference/choiced/human/vantag_preference, "antag")
	tag_pref(., /datum/preference/choiced/uplinklocation, "antag")

	//// VORE ////
	tag_pref(., /datum/preference/text/human/vore_egg_type, "vore", "basics")
	tag_pref(., /datum/preference/text/human/autohiss, "vore", "basics")
	tag_pref(., /datum/preference/numeric/human/sensorpref, "vore", "basics")
	tag_pref(., /datum/preference/toggle/human/ignore_shoes, "vore", "basics")
	// Crystal / backup
	tag_pref(., /datum/preference/toggle/human/capture_crystal, "vore", "backup")
	tag_pref(., /datum/preference/toggle/human/auto_backup_implant, "vore", "backup")
	tag_pref(., /datum/preference/toggle/human/borg_petting, "vore", "backup")
	// Directory subgroup
	tag_pref(., /datum/preference/toggle/human/show_in_directory, "vore", "directory")
	tag_pref(., /datum/preference/choiced/human/directory_tag, "vore", "directory")
	tag_pref(., /datum/preference/choiced/human/directory_gendertag, "vore", "directory")
	tag_pref(., /datum/preference/choiced/human/directory_sexualitytag, "vore", "directory")
	tag_pref(., /datum/preference/choiced/human/directory_erptag, "vore", "directory")
	tag_pref(., /datum/preference/text/human/directory_ad, "vore", "directory")
	// Thermal composite (editor)
	tag_pref(., /datum/preference/custom_heat, "vore", "thermal", PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/custom_cold, "vore", "thermal", PREF_WIDGET_HIDDEN)

	//// GAME (formerly: persistence + nif + pai + misc) ////
	// Persistence
	tag_pref(., /datum/preference/numeric/human/persistence_settings, "game", "persistence", PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/toggle/human/resleeve_lock, "game", "persistence")
	tag_pref(., /datum/preference/toggle/human/resleeve_scan, "game", "persistence")
	tag_pref(., /datum/preference/toggle/human/mind_scan, "game", "persistence")
	// PAI char config
	tag_pref(., /datum/preference/text/pai_name, "game", "pai")
	tag_pref(., /datum/preference/text/pai_description, "game", "pai", PREF_WIDGET_LONGTEXT)
	tag_pref(., /datum/preference/text/pai_role, "game", "pai")
	tag_pref(., /datum/preference/text/pai_ad, "game", "pai", PREF_WIDGET_LONGTEXT)
	tag_pref(., /datum/preference/text/pai_comments, "game", "pai", PREF_WIDGET_LONGTEXT)
	tag_pref(., /datum/preference/color/pai_eye_color, "game", "pai")
	tag_pref(., /datum/preference/text/pai_chassis, "game", "pai")
	tag_pref(., /datum/preference/text/pai_emotion, "game", "pai")
	// NIF (handled by editor)
	tag_pref(., /datum/preference/nif_path, "game", "nif", PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/numeric/nif_durability, "game", "nif", PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/nif_savedata, "game", "nif", PREF_WIDGET_HIDDEN)
	// Internal / hidden (derived flags, internal state)
	tag_pref(., /datum/preference/organ_data, null, null, PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/rlimb_data, null, null, PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/toggle/human/dirty_synth, null, null, PREF_WIDGET_HIDDEN)
	tag_pref(., /datum/preference/toggle/human/gross_meatbag, null, null, PREF_WIDGET_HIDDEN)

	// Apply all the tags to the actual singleton instances. Force-init the registry first
	// in case DM hasn't initialized it yet (GLOBAL_LIST_INIT ordering between this file and
	// _preference.dm isn't guaranteed).
	if(!GLOB.preference_entries)
		GLOB.preference_entries = init_preference_entries()
	if(!GLOB.preference_entries_by_key)
		GLOB.preference_entries_by_key = init_preference_entries_by_key()
	for(var/pref_type in .)
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		if(!pref)
			continue
		var/list/entry = .[pref_type]
		if(entry["category"])
			pref.category = entry["category"]
		if(entry["group"])
			pref.group = entry["group"]
		if(entry["widget"])
			pref.widget = entry["widget"]

/// Helper: stash a row in the metadata table. category/group/widget can each be null
/// (preserving whatever the pref already had set in its subtype declaration).
/proc/tag_pref(list/table, pref_type, category, group, widget)
	table[pref_type] = list(
		"category" = category,
		"group" = group,
		"widget" = widget,
	)
	// DQEdit — write the metadata onto the singleton so the auto-renderer picks it up.
	if(!GLOB.preference_entries)
		GLOB.preference_entries = init_preference_entries()
	var/datum/preference/instance = GLOB.preference_entries[pref_type]
	if(!instance)
		return
	if(category)
		instance.category = category
	if(group)
		instance.group = group
	if(widget)
		instance.widget = widget
