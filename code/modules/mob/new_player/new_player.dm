//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:33

/mob/new_player
	var/ready = 0
	var/spawning = 0			//Referenced when you want to delete the new_player later on in the code.
	var/totalPlayers = 0		//Player counts for the Lobby tab
	var/totalPlayersReady = 0
	var/has_respawned = FALSE	//Determines if we're using RESPAWN_MESSAGE
	var/datum/tgui_window/lobby_window = null
	var/datum/tgui_module/crew_manifest/new_player/manifest_dialog = null
	var/datum/tgui_module/late_choices/late_choices_dialog = null
	universal_speak = 1

	invisibility = INVISIBILITY_ABSTRACT

	density = FALSE
	stat = 2
	canmove = 0

	anchored = TRUE	//  don't get pushed around

	var/created_for

/mob/new_player/Destroy()
	GLOB.new_player_list -= src
	if(manifest_dialog)
		QDEL_NULL(manifest_dialog)
	if(late_choices_dialog)
		QDEL_NULL(late_choices_dialog)
	// clean up poll dialogs (privacy + player poll browser) migrated to TGUI
	if(privacy_poll_dialog)
		QDEL_NULL(privacy_poll_dialog)
	if(poll_browser_dialog)
		QDEL_NULL(poll_browser_dialog)
	. = ..()

/mob/new_player/get_status_tab_items()
	. = ..()
	. += ""

	. += "Game Mode: [SSticker.hide_mode ? "Secret" : "[config.mode_names[GLOB.master_mode]]"]"

	// if(SSvote.mode)
	// 	. += "Vote: [capitalize(SSvote.mode)] Time Left: [SSvote.time_remaining] s"

	if(SSticker.current_state == GAME_STATE_STARTUP)
		. += "Time To Start: Server Initializing"

	else if(SSticker.current_state == GAME_STATE_PREGAME)
		. += "Time To Start: [round(SSticker.timeLeft / 10, 1)][GLOB.round_progressing ? "" : " (DELAYED)"]"
		. += "Players: [totalPlayers]"
		. += "Players Ready: [totalPlayersReady]"
		totalPlayers = 0
		totalPlayersReady = 0
		var/datum/job/refJob = null
		for(var/mob/new_player/player in GLOB.player_list)
			refJob = player.client?.prefs.get_highest_job()
			var/obfuscate_key = player.read_preference(/datum/preference/toggle/obfuscate_key)
			var/obfuscate_job = player.read_preference(/datum/preference/toggle/obfuscate_job)
			if(obfuscate_key && obfuscate_job)
				. += "Anonymous User [player.ready ? "Ready!" : null]"
			else if(obfuscate_key)
				. += "Anonymous User [player.ready ? "(Playing as: [refJob ? refJob.title : "Unknown"])" : null]"
			else if(obfuscate_job)
				. += "[player.key] [player.ready ? "Ready!" : null]"
			else
				. += "[player.key] [player.ready ? "(Playing as: [refJob ? refJob.title : "Unknown"])" : null]"
			totalPlayers++
			if(player.ready)totalPlayersReady++

/mob/new_player/Topic(href, href_list[])
	if(!client)
		return 0
	if(!ready && href_list["preference"])
		client.prefs.process_link(src, href_list)
	if(href_list["open_station_news"])
		show_latest_news(GLOB.news_data.station_newspaper)


/mob/new_player/proc/handle_server_news()
	if(!client)
		return
	var/savefile/F = client.get_server_news()
	if(F)
		//client.prefs.lastnews = md5(F["body"]) //Chomp REMOVE
		//SScharacter_setup.queue_preferences_save(client.prefs) //Chomp REMOVE
		// start - handle reads correctly
		var/title
		F["title"] >> title
		F["title"] >> title //This is done twice on purpose. For some reason BYOND misses the first read, if performed before the world starts
		var/body
		F["body"] >> body
		// end

		var/dat = "<html><body><center>"
		dat += "<h1>[title]</h1>"
		dat += "<br>"
		dat += "[body]"
		dat += "<br>"
		dat += span_normal(span_italics("Last written by [F["author"]], on [F["timestamp"]]."))
		dat += "</center></body></html>"
		// structured TGUI AdminReport.
		dq_admin_report_html(src, "Server News", dat)

/mob/proc/time_till_respawn()
	if(!ckey)
		return -1 // What?

	var/timer = GLOB.respawn_timers[ckey]
	// No timer at all
	if(!timer)
		return 0
	// Special case, infinite timer
	if(timer == -1)
		return -1
	// Timer expired
	if(timer <= world.time)
		GLOB.respawn_timers -= ckey
		return 0
	// Timer still going
	return timer - world.time

/mob/new_player/proc/IsJobAvailable(rank)
	var/datum/job/job = SSjob.get_job(rank)
	if(!job)
		return 0
	if(!job.is_position_available())
		return 0
	if(jobban_isbanned(src,rank))
		return 0
	if(!job.player_old_enough(src.client))
		return 0
	if(!job.player_has_enough_playtime(src.client))
		return 0
	if(!is_job_whitelisted(src,rank))
		return 0
	if(!job.player_has_enough_pto(src.client))
		return 0
	// play_mode gating: cyborgs are the only option when chargen has
	// play_mode == "robot", and not an option for any other mode. Without this
	// a player who picked "Robot" in the species picker could still late-join
	// as a human; conversely, a human could late-join into the Cyborg slot.
	if(client?.prefs)
		var/play_mode = client.prefs.read_preference(/datum/preference/text/human/play_mode) || "human"
		var/is_cyborg_job = (rank == JOB_CYBORG || rank == JOB_ALT_ROBOT || rank == JOB_ALT_DRONE)
		if(play_mode == "robot" && !is_cyborg_job)
			return 0
		if(play_mode == "human" && is_cyborg_job)
			return 0
		if(play_mode == "pai")
			return 0
	return 1


/mob/new_player/proc/AttemptLateSpawn(rank)
	if (src != usr)
		return 0
	if(!SSticker || SSticker.current_state != GAME_STATE_PLAYING)
		to_chat(src, span_red("The round is either not ready, or has already finished..."))
		return 0
	if(!CONFIG_GET(flag/enter_allowed))
		to_chat(src, span_notice("There is an administrative lock on entering the game!"))
		return 0
	if(!IsJobAvailable(rank))
		tgui_alert_async(src,"[rank] is not available. Please try another.")
		return 0
	if(!spawn_checks_vr(rank)) return 0
	if(!client)
		return 0

	//Find our spawning point.
	var/list/join_props = SSjob.late_spawn(client, rank)

	if(!join_props)
		return

	var/turf/T = join_props["turf"]
	var/join_message = join_props["msg"]
	var/announce_channel = join_props["channel"] || "Common"

	if(!T || !join_message)
		return 0

	spawning = 1
	close_spawn_windows()

	var/obj/item/itemtf = join_props["itemtf"]
	if(itemtf && istype(itemtf, /obj/item/capture_crystal))
		var/obj/item/capture_crystal/cryst = itemtf
		if(cryst.spawn_mob_type)
			// We want to be a spawned mob instead of a person aaaaa
			var/mob/living/carrier = join_props["carrier"]
			var/vorgans = join_props["vorgans"]
			cryst.bound_mob = new cryst.spawn_mob_type(cryst)
			cryst.spawn_mob_type = null
			cryst.bound_mob.ai_holder_type = /datum/ai_holder/simple_mob/inert
			cryst.bound_mob.key = src.key
			log_and_message_admins("[key_name_admin(src)] joined [cryst.bound_mob] inside a capture crystal [ADMIN_FLW(cryst.bound_mob)]")
			if(vorgans)
				cryst.bound_mob.copy_from_prefs_vr()
			if(istype(carrier))
				cryst.capture(cryst.bound_mob, carrier)
			else
				//Something went wrong, but lets try to do as much as we can.
				cryst.bound_mob.capture_caught = TRUE
				cryst.persist_storable = FALSE
			cryst.update_icon()
			qdel(src)
			return

	SSjob.assign_role(src, rank, 1)

	var/mob/living/character = create_character(T)	//creates the human and transfers vars and mind
	character = SSjob.equip_rank(character, rank, 1)					//equips the human
	UpdateFactionList(character)

	var/datum/job/J = SSjob.get_job(rank)

	// AIs don't need a spawnpoint, they must spawn at an empty core
	if(J.mob_type & JOB_SILICON_AI)

		// IsJobAvailable for AI checks that there is an empty core available in this list
		var/obj/structure/AIcore/deactivated/C = GLOB.empty_playable_ai_cores[1]
		GLOB.empty_playable_ai_cores -= C

		character.loc = C.loc

		// AIize the character, but don't move them yet
		character = character.AIize(move = FALSE) // Dupe of code in /datum/controller/subsystem/ticker/proc/create_characters() for non-latespawn, unify?

		AnnounceCyborg(character, rank, "has been transferred to the empty core in \the [character.loc.loc]")
		SSticker.mode.latespawn(character)

		qdel(C) //Deletes empty core (really?)
		qdel(src) //Deletes new_player
		return

	// Equip our custom items only AFTER deploying to spawn points eh?
	equip_custom_items(character) // readded to enable custom_item.txt

	// Moving wheelchair if they have one
	if(character.buckled && istype(character.buckled, /obj/structure/bed/chair/wheelchair))
		character.buckled.loc = character.loc
		character.buckled.set_dir(character.dir)

	SSticker.mode.latespawn(character)

	if(rank == JOB_OUTSIDER)
		log_and_message_admins("has joined the round as non-crew. (<A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[T.x];Y=[T.y];Z=[T.z]'>JMP</a>)",character)
		if(!(J.mob_type & JOB_SILICON))
			SSticker.minds += character.mind
	else if(rank == JOB_ANOMALY)
		log_and_message_admins("has joined the round as anomaly. (<A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[T.x];Y=[T.y];Z=[T.z]'>JMP</a>)",character)
		if(!(J.mob_type & JOB_SILICON))
			SSticker.minds += character.mind
	else if(J.mob_type & JOB_SILICON)
		AnnounceCyborg(character, rank, join_message, announce_channel, character.z)
	else
		AnnounceArrival(character, rank, join_message, announce_channel, character.z)
		GLOB.data_core.manifest_inject(character)
		SSticker.minds += character.mind//Cyborgs and AIs handle this in the transform proc.	//TODO!!!!! ~Carn
	if(ishuman(character))
		if(character.client.prefs.read_preference(/datum/preference/toggle/human/auto_backup_implant)) // migrated pref
			var/obj/item/implant/backup/imp = new(src)

			if(imp.handle_implant(character,character.zone_sel.selecting))
				imp.post_implant(character)
	var/gut = join_props["voreny"]
	var/start_absorbed = join_props["absorb"]
	var/mob/living/prey = join_props["prey"]
	if(itemtf && istype(itemtf, /obj/item/capture_crystal))
		//We want to be in the crystal, not actually possessing the crystal.
		var/obj/item/capture_crystal/cryst = itemtf
		var/mob/living/carrier = join_props["carrier"]
		cryst.capture(character, carrier)
		character.forceMove(cryst)
		cryst.update_icon()
	else if(itemtf)
		character.tf_into(itemtf, TRUE, itemtf.name)
	else if(prey)
		character.copy_from_prefs_vr(1,1) //Yes I know we're reloading these, shut up
		var/obj/belly/gut_to_enter
		for(var/obj/belly/B in character.vore_organs)
			if(B.name == gut)
				gut_to_enter = B
				character.vore_selected = B
		var/datum/effect/effect/system/teleport_greyscale/tele = new /datum/effect/effect/system/teleport_greyscale()
		tele.set_up("#00FFFF", get_turf(prey))
		tele.start()
		character.forceMove(get_turf(prey))
		if(start_absorbed)
			prey.absorbed = 1
		prey.forceMove(gut_to_enter)
	else
		if(gut)
			if(start_absorbed)
				character.absorbed = 1
			character.forceMove(gut)

	character.client.init_verbs()
	qdel(src) // Delete new_player mob

/mob/new_player/proc/AnnounceCyborg(mob/living/character, rank, join_message, channel, zlevel)
	if (SSticker.current_state == GAME_STATE_PLAYING)
		var/list/zlevels = zlevel ? using_map.get_map_levels(zlevel, TRUE, om_range = DEFAULT_OVERMAP_RANGE) : null
		if(character.mind.role_alt_title)
			rank = character.mind.role_alt_title
		// can't use their name here, since cyborg namepicking is done post-spawn, so we'll just say "A new Cyborg has arrived"/"A new Android has arrived"/etc.
		GLOB.global_announcer.autosay("A new[rank ? " [rank]" : " visitor" ] [join_message ? join_message : "has arrived on the station"].", "Arrivals Announcement Computer", channel, zlevels)

/mob/new_player/proc/LateChoices()
	if(!late_choices_dialog)
		late_choices_dialog = new(src)
	late_choices_dialog.tgui_interact(src)

/mob/new_player/proc/create_character(turf/T)
	SHOULD_NOT_SLEEP(TRUE)
	spawning = 1
	close_spawn_windows()

	var/mob/living/carbon/human/new_character

	var/use_species_name
	var/datum/species/chosen_species
	var/pref_species = client.prefs.read_preference(/datum/preference/choiced/species)
	if(pref_species)
		chosen_species = GLOB.all_species[pref_species]
		use_species_name = chosen_species.get_station_variant() //Only used by pariahs atm.

	if(chosen_species && use_species_name)
		// Have to recheck admin due to no usr at roundstart. Latejoins are fine though.
		if(is_alien_whitelisted(src.client, chosen_species))
			new_character = new(T, use_species_name)

	if(!new_character)
		new_character = new(T)

	if(CONFIG_GET(flag/force_random_names))
		new_character.gender = pick(MALE, FEMALE)
		client.prefs.update_preference_by_type(/datum/preference/name/real_name, random_name(new_character.gender))
	else
		client.prefs.copy_to(new_character, icon_updates = TRUE)

	if(client && client.media)
		client.media.stop_music() // MAD JAMS cant last forever yo

	if(mind)
		mind.active = 0					//we wish to transfer the key manually
		mind.original_character = WEAKREF(new_character)
		mind.loaded_from_ckey = client.ckey
		mind.loaded_from_slot = client.prefs.default_slot
		mind.transfer_to(new_character)					//won't transfer key since the mind is not active

	new_character.name = real_name
	client.init_verbs()
	new_character.dna.ready_dna(new_character)
	new_character.dna.b_type = client.prefs.read_preference(/datum/preference/text/human/b_type) // migrated pref
	new_character.sync_dna_traits(TRUE) // Traitgenes Sync traits to genetics if needed
	new_character.sync_organ_dna()
	new_character.sync_addictions() // Handle round-start addictions
	new_character.initialize_vessel()

	// migrated language prefs to /datum/preference
	var/list/_alt_languages = client.prefs.read_preference(/datum/preference/alternate_languages)
	var/list/_lang_custom = client.prefs.read_preference(/datum/preference/language_custom_keys)
	for(var/lang in _alt_languages)
		var/datum/language/chosen_language = GLOB.all_languages[lang]
		if(chosen_language)
			if(is_lang_whitelisted(src,chosen_language) || (new_character.species && (chosen_language.name in new_character.species.secondary_langs)))
				new_character.add_language(lang)
	for(var/key in _lang_custom)
		if(_lang_custom[key])
			var/datum/language/keylang = GLOB.all_languages[_lang_custom[key]]
			if(keylang)
				new_character.language_keys[key] = keylang
	if(client.prefs.read_preference(/datum/preference/text/human/preferred_language)) // Do we have a preferred language?
		var/datum/language/def_lang = GLOB.all_languages[client.prefs.read_preference(/datum/preference/text/human/preferred_language)]
		if(def_lang)
			new_character.default_language = def_lang
	// And uncomment this, too.
	//new_character.dna.UpdateSE()

	SEND_SIGNAL(new_character, COMSIG_HUMAN_DNA_FINALIZED)

	// Do the initial caching of the player's body icons.
	new_character.force_update_limbs()
	new_character.update_icons_body()
	new_character.update_transform()

	new_character.key = key		//Manually transfer the key to log them in

	return new_character

/mob/new_player/proc/ViewManifest()
	if(!manifest_dialog)
		manifest_dialog = new(src)
	manifest_dialog.tgui_interact(src)

/mob/new_player/Move()
	return 0

/mob/new_player/proc/close_spawn_windows()
	manifest_dialog?.close_ui()
	late_choices_dialog?.close_ui()
	// legacy browse() cleanup for latechoices/preferences/News;
	// those windows are all TGUI now, so the close calls target nothing.

/mob/new_player/get_species()
	var/datum/species/chosen_species
	var/pref_species = client.prefs.read_preference(/datum/preference/choiced/species)
	if(pref_species)
		chosen_species = GLOB.all_species[pref_species]

	if(!chosen_species)
		return SPECIES_HUMAN

	if(is_alien_whitelisted(src.client, chosen_species))
		return chosen_species.name

	return SPECIES_HUMAN

/mob/new_player/get_gender()
	if(!client || !client.prefs) ..()
	return client.prefs.read_preference(/datum/preference/choiced/gender/biological)

/mob/new_player/is_ready()
	return ready && ..()

// Prevents lobby players from seeing say, even with ghostears
/mob/new_player/hear_say(list/message_pieces, verb = "says", italics = 0, mob/speaker = null)
	return

/mob/new_player/hear_holopad_talk(list/message_pieces, verb = "says", mob/speaker = null)
	return

/mob/new_player/hear_holopad_talk(list/message_pieces, verb = "says", mob/speaker = null)
	return

// Prevents lobby players from seeing emotes, even with ghosteyes
/mob/new_player/show_message(msg, type, alt, alt_type)
	return

/mob/new_player/hear_radio()
	return

/mob/new_player/MayRespawn()
	return TRUE


// === merged from new_player_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/mob/new_player/proc/spawn_checks_vr(rank)
	var/pass = TRUE
	var/datum/job/J = SSjob.get_job(rank)

	if(!J)
		NOTICE("Couldn't find job: [rank] for spawn_checks_vr, panic-returning that it's fine to spawn.")
		return TRUE

	//No Flavor Text
	if (CONFIG_GET(flag/require_flavor) && !(J.mob_type & JOB_SILICON) && (!LAZYACCESS(client?.prefs?.read_preference(/datum/preference/flavor_texts), "general") || length(LAZYACCESS(client.prefs.read_preference(/datum/preference/flavor_texts), "general")) < 30)) // migrated
		to_chat(src,span_warning("Please set your general flavor text to give a basic description of your character. Set it using the 'Set Flavor text' button on the 'General' tab in character setup, and choosing 'General' category."))
		pass = FALSE

	//No OOC notes
	if (CONFIG_GET(flag/allow_metadata) && (!client?.prefs?.read_preference(/datum/preference/text/living/ooc_notes) || length(client.prefs.read_preference(/datum/preference/text/living/ooc_notes)) < 15))
		to_chat(src,span_warning("Please set informative OOC notes related to RP/ERP preferences. Set them using the 'OOC Notes' button on the 'General' tab in character setup."))
		pass = FALSE

	//Are they on the VERBOTEN LIST?
	if (GLOB.prevent_respawns.Find(client?.prefs?.read_preference(/datum/preference/name/real_name)))
		to_chat(src,span_warning("You've already quit the round as this character. You can't go back now that you've free'd your job slot. Play another character, or wait for the next round."))
		pass = FALSE

	//Do they have their scale properly setup?
	if(!client?.prefs?.read_preference(/datum/preference/numeric/human/size_multiplier)) // migrated
		pass = FALSE
		to_chat(src,span_warning("You have not set your scale yet. Do this on the VORE tab in character setup."))

	//Can they play?
	if(!is_alien_whitelisted(src.client,GLOB.all_species[client?.prefs?.read_preference(/datum/preference/choiced/species)]) && !check_rights(R_ADMIN, 0))
		pass = FALSE
		to_chat(src,span_warning("You are not allowed to spawn in as this species."))

	// Check species job bans... (Only used for shadekin)
	if(J.is_species_banned(client?.prefs?.read_preference(/datum/preference/choiced/species), client?.prefs?.read_preference(/datum/preference/organ_data)?[O_BRAIN]))
		pass = FALSE
		to_chat(src,span_warning("Your species is not permitted to take this role or job."))

	//Custom species checks
	if (client?.prefs?.read_preference(/datum/preference/choiced/species) == SPECIES_CUSTOM)

		//Didn't name it
		if(!client?.prefs?.read_preference(/datum/preference/text/human/custom_species)) // migrated
			pass = FALSE
			to_chat(src,span_warning("You have to name your custom species. Do this on the VORE tab in character setup."))

	//Check traits/costs
	// migrated traits prefs (typed_list base)
	var/list/_pos_traits = client.prefs.read_preference(/datum/preference/typed_list/traits/pos_traits)
	var/list/_neu_traits = client.prefs.read_preference(/datum/preference/typed_list/traits/neu_traits)
	var/list/_neg_traits = client.prefs.read_preference(/datum/preference/typed_list/traits/neg_traits)
	var/list/megalist = _pos_traits + _neu_traits + _neg_traits
	var/points_left = client.prefs.read_preference(/datum/preference/numeric/human/starting_trait_points)
	var/traits_left = client.prefs.read_preference(/datum/preference/numeric/human/max_traits)
	var/pref_synth = client.prefs.read_preference(/datum/preference/toggle/human/dirty_synth) // migrated
	var/pref_meat = client.prefs.read_preference(/datum/preference/toggle/human/gross_meatbag) // migrated
	for(var/datum/trait/T as anything in megalist)
		var/cost = GLOB.traits_costs[T]

		if(T.category == TRAIT_TYPE_POSITIVE)
			traits_left--

		//A trait was removed from the game
		if(isnull(cost))
			pass = FALSE
			to_chat(src,span_warning("Your species is not playable. One or more traits appear to have been removed from the game or renamed. Enter character setup to correct this."))
			break
		else
			points_left -= GLOB.traits_costs[T]

		var/take_flags = initial(T.can_take)
		if((pref_synth && !(take_flags & SYNTHETICS)) || (pref_meat && !(take_flags & ORGANICS)))
			pass = FALSE
			to_chat(src, span_warning("Some of your traits are not usable by your character type (synthetic traits on organic, or vice versa)."))
	// start
	if(J.camp_protection && round_duration_in_ds < CONFIG_GET(number/job_camp_time_limit))
		if(SSjob.restricted_keys.len)
			var/list/check = SSjob.restricted_keys[J.title]
			if(client.ckey in check)
				to_chat(src, span_danger("[J.title] is not presently selectable because you played as it last round. It will become available to you in [round((CONFIG_GET(number/job_camp_time_limit) - round_duration_in_ds) / 600)] minutes, if slots remain open."))
				pass = FALSE
	// end

	//CHOMP Addition Begin
	// migrated neu_traits
	if(_neu_traits)
		for(var/T in _neu_traits)
			var/datum/trait/instance = GLOB.all_traits[T]
			if(client.prefs.read_preference(/datum/preference/choiced/species) in instance.banned_species)
				pass = FALSE
				to_chat(src,span_warning("One of your traits, [instance.name], is not available for your species! Please fix this conflict and then try again."))
			else if(LAZYLEN(instance.allowed_species) && !(client.prefs.read_preference(/datum/preference/choiced/species) in instance.allowed_species)) //We use else if here, so as to prevent getting two errors for one trait.
				pass = FALSE
				to_chat(src,span_warning("One of your traits, [instance.name], is not available for your species! Please fix this conflict and then try again."))
	//CHOMP Addition End

	//Went into negatives
	if(points_left < 0 || traits_left < 0)
		pass = FALSE
		to_chat(src,span_warning("Your species is not playable. Reconfigure your traits on the VORE tab. Trait points: [points_left]. Traits left: [traits_left]."))

	//Final popup notice
	if (!pass)
		tgui_alert_async(src,"There were problems with spawning your character. Check your message log for details.","Error")
	return pass
