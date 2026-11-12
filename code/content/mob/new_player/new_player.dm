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


/mob/new_player/get_status_tab_items()
	. = ..()
	. += ""

	. += "Game Mode: [ticker_hide_mode() ? "Secret" : "[config.mode_names[GLOB.master_mode]]"]"

	// if(GLOB.vote_service.mode)
	// 	. += "Vote: [capitalize(GLOB.vote_service.mode)] Time Left: [GLOB.vote_service.time_remaining] s"

	if(ticker_current_state() == GAME_STATE_STARTUP)
		. += "Time To Start: Server Initializing"

	else if(ticker_current_state() == GAME_STATE_PREGAME)
		. += "Time To Start: [round(ticker_timeLeft() / 10, 1)][GLOB.round_progressing ? "" : " (DELAYED)"]"
		. += "Players: [totalPlayers]"
		. += "Players Ready: [totalPlayersReady]"
		totalPlayers = 0
		totalPlayersReady = 0
		var/datum/job/refJob = null
		for(var/mob/new_player/player in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
			refJob = player.client?.prefs.get_highest_job()
			var/obfuscate_key = FALSE
			var/obfuscate_job = FALSE
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
		return RESPAWN_NEVER // What?

	var/datum/respawn_timer/timer = LAZYACCESS(SSmobs.respawn_timers, ckey)
	// No timer at all
	if(!timer)
		return 0
	if(timer.forbidden)
		return RESPAWN_NEVER
	// Timer expired
	var/waited = ELAPSED(timer, started_at, CLOCK_WORLD)
	if(waited >= timer.duration)
		SSmobs.clear_respawn_wait(ckey)
		return 0
	// Timer still going
	return timer.duration - waited

MSG_DEF_SELF(join/no_such_job, "There is no such job.")
MSG_DEF_SELF(join/job_full, "That job has no open positions.")
MSG_DEF_SELF(join/jobbanned, "You are banned from that job.")
MSG_DEF_SELF(join/too_new, "Your account is too new for that job.")
MSG_DEF_SELF(join/not_enough_playtime, "You haven't played enough for that job.")
MSG_DEF_SELF(join/not_enough_pto, "You don't have enough PTO for that job.")
MSG_DEF_SELF(join/wrong_play_mode, "Your play mode doesn't allow that job.")

/// Why this player can't join as `rank` now, or null (admission.md D7: the join's gates in order, each with its own reason, where the
/// old isnull(job_join_refusal()) answered 0 and the caller showed "not available").
/mob/new_player/proc/job_join_refusal(rank)
	var/datum/job/job = SSjob.get_job(rank)
	if(!job)
		return /datum/msg/join/no_such_job
	if(!job.is_position_available())
		return /datum/msg/join/job_full
	if(jobban_isbanned(src,rank))
		return /datum/msg/join/jobbanned
	if(!job.player_old_enough(src.client))
		return /datum/msg/join/too_new
	if(!job.player_has_enough_playtime(src.client))
		return /datum/msg/join/not_enough_playtime
	. = job_whitelist_refusal(src, rank)
	if(.)
		return .
	if(!job.player_has_enough_pto(src.client))
		return /datum/msg/join/not_enough_pto
	// play_mode gating: cyborgs are the only option when chargen has
	// play_mode == "robot", and not an option for any other mode. Without this
	// a player who picked "Robot" in the species picker could still late-join
	// as a human; conversely, a human could late-join into the Cyborg slot.
	if(client?.prefs)
		var/play_mode = client.prefs.read_preference(/datum/preference/text/human/play_mode) || "human"
		. = play_mode_rank_refusal(play_mode, rank)
		if(.)
			return .
	return null

/mob/new_player/proc/AttemptLateSpawn(rank, mob/user, list/answers = null)
	if (src != user)
		return 0
	return do_late_spawn(rank, answers)

/// Joins as `rank`. Vore and item spawnpoints ask the joiner first (the join op's `answers`), then the pred, prey or carrier:
/// that answer (`consent`) runs this again, so every check below is re-made before the joiner spawns.
/mob/new_player/proc/do_late_spawn(rank, list/answers = null, consent = null)
	if(client?.login_hold_refuses())
		return 0
	if(spawning || QDELETED(src))
		return 0
	if(!SSticker || ticker_current_state() != GAME_STATE_PLAYING)
		to_chat(src, span_red("The round is either not ready, or has already finished..."))
		return 0
	if(!CONFIG_GET(flag/enter_allowed))
		to_chat(src, span_notice("There is an administrative lock on entering the game!"))
		return 0
	var/refused = job_join_refusal(rank)
	if(refused)
		tgui_alert_async(src,"[rank] is not available: [reason_text(refused)]")
		return 0
	if(!spawn_checks_vr(rank)) return 0
	if(!client)
		return 0

	var/join_started = TICK_USAGE_REAL
	//Find our spawning point.
	var/list/join_props = SSjob.late_spawn(client, rank, src, answers, consent)

	if(!join_props)
		return

	var/turf/T = join_props["turf"]
	var/join_message = join_props["msg"]
	var/announce_channel = join_props["channel"] || "Common"

	if(!T || !join_message)
		return 0

	set_spawning(1)
	close_spawn_windows()

	var/obj/item/itemtf = join_props["itemtf"]
	if(itemtf && istype(itemtf, /obj/item/capture_crystal))
		var/obj/item/capture_crystal/cryst = itemtf
		if(cryst.spawn_mob_type)
			// We want to be a spawned mob instead of a person aaaaa
			var/mob/living/carrier = join_props["carrier"]
			var/vorgans = join_props["vorgans"]
			rel_set(cryst, nameof(cryst.bound_mob), new cryst.spawn_mob_type(cryst))
			cryst.set_spawn_mob_type(null)
			bind_player(cryst.bound_mob, src.key)
			log_and_message_admins("[key_name_admin(src)] joined [cryst.bound_mob] inside a capture crystal [ADMIN_FLW(cryst.bound_mob)]", src)
			if(vorgans)
				cryst.bound_mob.copy_from_prefs_vr()
			if(istype(carrier))
				cryst.capture(cryst.bound_mob, carrier)
			else
				//Something went wrong, but lets try to do as much as we can.
				STATE_SET(cryst.bound_mob, capture, capture_caught, TRUE)
				cryst.set_persist_storable(FALSE)
			spent(src)
			return

	var/spawn_point_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - join_started)
	SSjob.assign_role(src, rank, 1)

	var/phase_started = TICK_USAGE_REAL
	var/mob/living/character = create_character(T)	//creates the human and transfers vars and mind
	var/create_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - phase_started)
	phase_started = TICK_USAGE_REAL
	character = SSjob.equip_rank(character, rank, 1)					//equips the human
	var/equip_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - phase_started)
	UpdateFactionList(character)
	SSshuttles.body_placed(character)

	var/datum/job/J = SSjob.get_job(rank)

	// AIs don't need a spawnpoint, they must spawn at an empty core
	if(J.mob_type & JOB_SILICON_AI)

		// job_join_refusal for AI checks that there is an empty core available in this list
		var/obj/structure/AIcore/deactivated/C = REGISTRY_MEMBERS(REGISTRY_EMPTY_AI_CORES)[1]
		registry_leave(REGISTRY_EMPTY_AI_CORES, C)

		character.forceMove(C.loc)

		// AIize the character, but don't move them yet
		character = character.AIize(move = FALSE) // Dupe of code in /datum/system/ticker/proc/create_characters() for non-latespawn, unify?

		AnnounceCyborg(character, rank, "has been transferred to the empty core in \the [character.loc.loc]")
		ticker_mode().latespawn(character)

		spent(C) //Deletes empty core (really?)
		spent(src) //Deletes new_player
		return

	// Equip our custom items only AFTER deploying to spawn points eh?
	equip_custom_items(character) // readded to enable custom_item.txt

	// Moving wheelchair if they have one
	if(character?.buckled_to() && istype(character?.buckled_to(), /obj/structure/bed/chair/wheelchair))
		var/atom/movable/_tmp_buck_32 = character?.buckled_to()
		_tmp_buck_32.forceMove(character.loc)
		var/atom/movable/_tmp_buck_33 = character?.buckled_to()
		_tmp_buck_33.set_dir(character.dir)

	ticker_mode().latespawn(character)

	if(rank == JOB_OUTSIDER)
		log_and_message_admins("has joined the round as non-crew. (<A href='byond://?_src_=holder;[HREF_TOKEN_PLACEHOLDER];adminplayerobservecoodjump=1;X=[T.x];Y=[T.y];Z=[T.z]'>JMP</a>)",character)
		if(!(J.mob_type & JOB_SILICON))
			SSticker.remember_mind(character.mind)
	else if(rank == JOB_ANOMALY)
		log_and_message_admins("has joined the round as anomaly. (<A href='byond://?_src_=holder;[HREF_TOKEN_PLACEHOLDER];adminplayerobservecoodjump=1;X=[T.x];Y=[T.y];Z=[T.z]'>JMP</a>)",character)
		if(!(J.mob_type & JOB_SILICON))
			SSticker.remember_mind(character.mind)
	else if(J.mob_type & JOB_SILICON)
		AnnounceCyborg(character, rank, join_message, announce_channel, character.z)
	else
		// The arrival announcement and the manifest record (its photos are two composited icons: 50-380 ms) follow a tick later: they ride the join's
		// frame otherwise, and nothing the joiner does in that tick reads either.
		after(character, 1 TICKS, GLOBAL_PROC_REF(latejoin_register), with = list(character, rank, join_message, announce_channel, character.z))
		SSticker.remember_mind(character.mind) //Cyborgs and AIs handle this in the transform proc.	//TODO!!!!! ~Carn
	if(ishuman(character))
	var/gut = join_props["voreny"]
	var/start_absorbed = join_props["absorb"]
	var/mob/living/prey = join_props["prey"]
	if(itemtf && istype(itemtf, /obj/item/capture_crystal))
		//We want to be in the crystal, not actually possessing the crystal.
		var/obj/item/capture_crystal/cryst = itemtf
		var/mob/living/carrier = join_props["carrier"]
		cryst.capture(character, carrier)
		character.forceMove(cryst)
	else if(itemtf)
		character.tf_into(itemtf, TRUE, itemtf.name)
	else if(prey)
		character.copy_from_prefs_vr(1,1) //Yes I know we're reloading these, shut up
		var/obj/belly/gut_to_enter
		for(var/obj/belly/B in character.vore_organs)
			if(B.name == gut)
				gut_to_enter = B
				set_vore_selected(character, B) // a pointer at one of vore_organs
		var/datum/effect/effect/system/teleport_greyscale/tele = new /datum/effect/effect/system/teleport_greyscale()
		tele.set_up("#00FFFF", get_turf(prey))
		tele.start()
		character.forceMove(get_turf(prey))
		if(start_absorbed)
			prey.set_absorbed(1)
		prey.forceMove(gut_to_enter)
	else
		if(gut)
			if(start_absorbed)
				character.set_absorbed(1)
			character.forceMove(gut)

	character.client.init_verbs()
	log_world("JOIN_TIMING: [key_name(character)] as [rank]: spawn point [round(spawn_point_ms, 0.1)] ms, body [round(create_ms, 0.1)] ms, equip [round(equip_ms, 0.1)] ms, whole join [round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - join_started), 0.1)] ms (the announcement and manifest record follow a tick later: LATEJOIN_REGISTER)")
	spent(src) // Delete new_player mob

/// The part of a join that follows a tick after the body is placed: the arrival announcement and the manifest record, timed (LATEJOIN_REGISTER).
/proc/latejoin_register(mob/living/carbon/human/character, rank, join_message, channel, zlevel)
	if(QDELETED(character) || !character.mind)
		return
	var/started = TICK_USAGE_REAL
	AnnounceArrival(character, rank, join_message, channel, zlevel)
	var/announced_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	GLOB.data_core.manifest_inject(character)
	log_world("LATEJOIN_REGISTER: [character.real_name]: announcement [round(announced_ms, 0.1)] ms, manifest record [round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) - announced_ms, 0.1)] ms")

/// The pred, prey or carrier answered (or, with its no-warning pref, let the question lapse): the join goes on with that answer.
/mob/new_player/proc/late_spawn_consented(datum/act/request/A)
	var/datum/prompt/choice/late_spawn_consent/asked = A.request
	if(!asked || QDELETED(asked.answerer))
		return
	var/consent = A.answer ? A.answer.value : asked.cancel_answer
	if(isnull(consent))
		return
	do_late_spawn(asked.rank, asked.answers, consent)

/mob/new_player/proc/AnnounceCyborg(mob/living/character, rank, join_message, channel, zlevel)
	if (ticker_current_state() == GAME_STATE_PLAYING)
		var/list/zlevels = zlevel ? using_map.get_map_levels(zlevel, TRUE, overmap_range = DEFAULT_OVERMAP_RANGE) : null
		if(character.mind.role_alt_title)
			rank = character.mind.role_alt_title
		// can't use their name here, since cyborg namepicking is done post-spawn, so we'll just say "A new Cyborg has arrived"/"A new Android has arrived"/etc.
		GLOB.global_announcer.autosay("A new[rank ? " [rank]" : " visitor" ] [join_message ? join_message : "has arrived on the station"].", "Arrivals Announcement Computer", channel, zlevels)

/mob/new_player/proc/LateChoices()
	if(!late_choices_dialog)
		rel_set(src, nameof(late_choices_dialog), new /datum/tgui_module/late_choices(src))
	late_choices_dialog.tgui_interact(src)

/mob/new_player/proc/create_character(turf/T)
	SHOULD_NOT_SLEEP(TRUE)
	set_spawning(1)
	close_spawn_windows()

	var/mob/living/carbon/human/new_character
	var/step_started = TICK_USAGE_REAL
	var/list/step_ms = list()

	var/use_species_name
	var/datum/species/chosen_species
	var/pref_species = client.prefs.read_preference(/datum/preference/choiced/species)
	if(pref_species)
		chosen_species = GLOB.all_species[pref_species]
		use_species_name = chosen_species.get_station_variant() //Only used by pariahs atm.

	if(chosen_species && use_species_name)
		// Have to recheck admin due to no usr at roundstart. Latejoins are fine though.
		if(isnull(alien_whitelist_refusal(src.client, chosen_species)))
			new_character = new(T, use_species_name)

	if(!new_character)
		new_character = new(T)

	step_ms["new human"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - step_started)
	step_started = TICK_USAGE_REAL
	if(CONFIG_GET(flag/force_random_names))
		new_character.set_gender(pick(MALE, FEMALE))
		client.prefs.update_preference_by_type(/datum/preference/name/real_name, random_name(new_character.gender))
	else
		client.prefs.copy_to(new_character, icon_updates = TRUE)

	step_ms["prefs copy_to"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - step_started)
	step_started = TICK_USAGE_REAL
	if(client && client.media)
		client.media.stop_music() // MAD JAMS cant last forever yo

	if(mind)
		mind.active = 0					//we wish to transfer the key manually
		rel_set(mind, nameof(mind.original_character), new_character)
		mind.loaded_from_ckey = client.ckey
		mind.loaded_from_slot = client.prefs.default_slot
		mind.transfer_to(new_character)					//won't transfer key since the mind is not active

	new_character.name = real_name
	client.init_verbs()
	step_ms["mind transfer, verbs"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - step_started)
	step_started = TICK_USAGE_REAL
	new_character.dna.ready_dna(new_character)
	new_character.dna.set_b_type(text_or_null(client.prefs.read_preference(/datum/preference/text/human/b_type))) // migrated pref
	new_character.sync_dna_traits(TRUE) // Traitgenes Sync traits to genetics if needed
	new_character.sync_organ_dna()
	new_character.sync_addictions() // Handle round-start addictions
	new_character.initialize_vessel()

	step_ms["dna, traits, organ dna, vessel"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - step_started)
	step_started = TICK_USAGE_REAL
	// migrated language prefs to /datum/preference
	var/list/_alt_languages = client.prefs.read_preference(/datum/preference/alternate_languages)
	for(var/lang in _alt_languages)
		var/datum/language/chosen_language = GLOB.all_languages[lang]
		if(chosen_language)
			if(is_lang_whitelisted(src,chosen_language) || (new_character.species && (chosen_language.name in new_character.species.secondary_langs)))
				new_character.add_language(lang)
	new_character.apply_language_prefs(client.prefs)
	// And uncomment this, too.
	//new_character.dna.UpdateSE()

	step_ms["languages"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - step_started)
	step_started = TICK_USAGE_REAL

	PUBLISH(new_character, human_dna_finalized)
	step_ms["human_dna_finalized"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - step_started)
	step_started = TICK_USAGE_REAL

	// Do the initial caching of the player's body icons.
	new_character.force_update_limbs()
	new_character.update_transform()
	step_ms["force_update_limbs, transform"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - step_started)
	step_started = TICK_USAGE_REAL

	bind_player(new_character, key)		//Manually transfer the key to log them in
	step_ms["bind_player"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - step_started)

	var/steps = ""
	for(var/step_name in step_ms)
		steps += ", [step_name] [round(step_ms[step_name], 0.1)] ms"
	log_world("JOIN_TIMING_BODY: [key_name(new_character)]: [copytext(steps, 3)]")

	return new_character

/mob/new_player/proc/ViewManifest()
	if(!manifest_dialog)
		rel_set(src, nameof(manifest_dialog), new /datum/tgui_module/crew_manifest/new_player(src))
	manifest_dialog.tgui_interact(src)

/mob/new_player/Move(atom/newloc, direct = 0, movetime)
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

	if(isnull(alien_whitelist_refusal(src.client, chosen_species)))
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

// Prevents lobby players from seeing emotes, even with ghosteyes
/mob/new_player/show_message(msg, type, alt, alt_type)
	return

/mob/new_player/hear_radio()
	return

/mob/new_player/MayRespawn()
	return TRUE

/// Whether the joiner may spawn as `rank`; `quiet` checks without telling them why (the join op asks no question of someone who will be refused).
/mob/new_player/proc/spawn_checks_vr(rank, quiet = FALSE)
	var/list/problems = spawn_check_problems(rank)
	if(!length(problems))
		return TRUE
	if(!quiet)
		for(var/problem in problems)
			to_chat(src, problem)
		tgui_alert_async(src,"There were problems with spawning your character. Check your message log for details.","Error")
	return FALSE

/// Why the joiner may not spawn as `rank`: one message per problem, or null when they may. Reads only; the caller tells them.
/mob/new_player/proc/spawn_check_problems(rank)
	var/list/problems
	var/pass = TRUE
	var/datum/job/J = SSjob.get_job(rank)

	if(!J)
		NOTICE("Couldn't find job: [rank] for spawn_checks_vr, panic-returning that it's fine to spawn.")
		return null

	//No Flavor Text
	if (CONFIG_GET(flag/require_flavor) && !(J.mob_type & JOB_SILICON) && (!LAZYACCESS(client?.prefs?.read_preference(/datum/preference/flavor_texts), "general") || length(LAZYACCESS(client.prefs.read_preference(/datum/preference/flavor_texts), "general")) < 30)) // migrated
		LAZYADD(problems, span_warning("Please set your general flavor text to give a basic description of your character. Set it using the 'Set Flavor text' button on the 'General' tab in character setup, and choosing 'General' category."))
		pass = FALSE

	//No OOC notes
	if (CONFIG_GET(flag/allow_metadata) && (!client?.prefs?.read_preference(/datum/preference/text/living/ooc_notes) || length(client.prefs.read_preference(/datum/preference/text/living/ooc_notes)) < 15))
		LAZYADD(problems, span_warning("Please set informative OOC notes related to RP/ERP preferences. Set them using the 'OOC Notes' button on the 'General' tab in character setup."))
		pass = FALSE

	//Are they on the VERBOTEN LIST?
	if (GLOB.prevent_respawns.Find(client?.prefs?.read_preference(/datum/preference/name/real_name)))
		LAZYADD(problems, span_warning("You've already quit the round as this character. You can't go back now that you've free'd your job slot. Play another character, or wait for the next round."))
		pass = FALSE

	//Do they have their scale properly setup?
	if(!client?.prefs?.read_preference(/datum/preference/numeric/human/size_multiplier)) // migrated
		pass = FALSE
		LAZYADD(problems, span_warning("You have not set your scale yet. Do this on the VORE tab in character setup."))

	//Can they play?
	if(alien_whitelist_refusal(src.client,GLOB.all_species[client?.prefs?.read_preference(/datum/preference/choiced/species)]) && !admin_require(client, R_ADMIN, "spawn_checks_vr", 0))
		pass = FALSE
		LAZYADD(problems, span_warning("You are not allowed to spawn in as this species."))

	// Check species job bans... (Only used for shadekin)
	if(J.is_species_banned(client?.prefs?.read_preference(/datum/preference/choiced/species), client?.prefs?.read_preference(/datum/preference/organ_data)?[O_BRAIN]))
		pass = FALSE
		LAZYADD(problems, span_warning("Your species is not permitted to take this role or job."))

	//Custom species checks
	if (client?.prefs?.read_preference(/datum/preference/choiced/species) == SPECIES_CUSTOM)

		//Didn't name it
		if(!client?.prefs?.read_preference(/datum/preference/text/human/custom_species)) // migrated
			pass = FALSE
			LAZYADD(problems, span_warning("You have to name your custom species. Do this on the VORE tab in character setup."))

	//Check traits/costs
	// migrated traits prefs (typed_list base)
	var/list/_pos_traits = client.prefs.read_preference(/datum/preference/typed_list/traits/pos_traits)
	var/list/_neu_traits = client.prefs.read_preference(/datum/preference/typed_list/traits/neu_traits)
	var/list/_neg_traits = client.prefs.read_preference(/datum/preference/typed_list/traits/neg_traits)
	var/list/megalist = _pos_traits + _neu_traits + _neg_traits
	var/points_left = client.prefs.trait_point_budget()
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
			LAZYADD(problems, span_warning("Your species is not playable. One or more traits appear to have been removed from the game or renamed. Enter character setup to correct this."))
			break
		else
			points_left -= GLOB.traits_costs[T]

		var/take_flags = initial(T.can_take)
		if((pref_synth && !(take_flags & SYNTHETICS)) || (pref_meat && !(take_flags & ORGANICS)))
			pass = FALSE
			LAZYADD(problems, span_warning("Some of your traits are not usable by your character type (synthetic traits on organic, or vice versa)."))
	// start
	if(J.camp_protection && round_duration_in_ds < CONFIG_GET(number/job_camp_time_limit))
		if(SSjob.has_restricted_keys())
			if(SSjob.is_restricted_key(J.title, client.ckey))
				LAZYADD(problems, span_danger("[J.title] is not presently selectable because you played as it last round. It will become available to you in [round((CONFIG_GET(number/job_camp_time_limit) - round_duration_in_ds) / 600)] minutes, if slots remain open."))
				pass = FALSE
	// end

	//ition Begin
	// migrated neu_traits
	if(_neu_traits)
		for(var/T in _neu_traits)
			var/datum/trait/instance = GLOB.all_traits[T]
			if(client.prefs.read_preference(/datum/preference/choiced/species) in instance.banned_species)
				pass = FALSE
				LAZYADD(problems, span_warning("One of your traits, [instance.name], is not available for your species! Please fix this conflict and then try again."))
			else if(LAZYLEN(instance.allowed_species) && !(client.prefs.read_preference(/datum/preference/choiced/species) in instance.allowed_species)) //We use else if here, so as to prevent getting two errors for one trait.
				pass = FALSE
				LAZYADD(problems, span_warning("One of your traits, [instance.name], is not available for your species! Please fix this conflict and then try again."))
	//ition End

	//Went into negatives
	if(points_left < 0 || traits_left < 0)
		pass = FALSE
		LAZYADD(problems, span_warning("Your species is not playable. Reconfigure your traits on the VORE tab. Trait points: [points_left]. Traits left: [traits_left]."))

	if(!pass && !length(problems))
		LAZYADD(problems, span_warning("You may not spawn as this character."))
	return problems

// The window belongs to the client (tgui_window); the lobby only drives it.
