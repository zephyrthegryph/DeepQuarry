
/obj/machinery/transhuman/autoresleever
	name = "automatic resleever"
	desc = "Uses advanced technology to detect when someone needs to be resleeved, and automatically prints and sleeves them into a new body. It even generates its own biomass!"
	icon = 'icons/obj/machines/autoresleever.dmi'
	icon_state = "autoresleever"
	density = TRUE
	anchored = TRUE
	var/equip_body = FALSE				//If true, this will spawn the person with equipment
	var/default_job = JOB_ALT_VISITOR		//The job that will be assigned if equip_body is true and the ghost doesn't have a job
	var/ghost_spawns = FALSE			//If true, allows ghosts who haven't been spawned yet to spawn
	var/vore_respawn = 5 MINUTES		//The time to wait if you died from vore
	var/respawn = 30 MINUTES			//The time to wait if you didn't die from vore
	var/spawn_slots = -1				//How many people can be spawned from this? If -1 it's unlimited
	var/spawntype						//The kind of mob that will be spawned, if set.

REGISTRY_MEMBERSHIP(/obj/machinery/transhuman/autoresleever, REGISTRY_AUTORESLEEVERS)

/// The look (the draw sweep: from its template).
/obj/machinery/transhuman/autoresleever/draw(datum/look/look)
	..()
	look.state("autoresleever[appearance_faulty() ? "-o" : ""]")

/obj/machinery/transhuman/autoresleever/proc/appearance_faulty()
	return has_stat(BROKEN | MAINT | EMPED)

CAPABILITIES(/obj/machinery/transhuman/autoresleever)
	op("autoresleever_interaction_ghost", observer(), label("Respawn"), asks(/datum/prompt/choice, fields = list("question" = computed(PROC_REF(special_question)), "title" = "Creachur", "choices" = list("No", "Yes"), "buttons" = TRUE, "timeout" = 0), step = "k54", when = PROC_REF(asks_special)), asks(/datum/prompt/choice, fields = list("question" = "Would you like to be spawned here as your presently loaded character?", "title" = "Spawn here", "choices" = list("No", "Yes"), "buttons" = TRUE, "timeout" = 0), step = "k57", when = PROC_REF(asks_loaded)), then(PROC_REF(autoresleever_interaction_ghost)))
	op("autoresleever_interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(autoresleever_interaction_item)))

/// The question of a special spawner.
/obj/machinery/transhuman/autoresleever/proc/special_question(datum/act/op/A)
	return "This [src] spawns something special, would you like to play as it?"

/// A ghost with no mind is asked whether to play the special spawn of this resleever.
/obj/machinery/transhuman/autoresleever/proc/asks_special(datum/act/op/A)
	var/mob/observer/dead/user = A.actor
	return spawn_slots != 0 && !user.mind && spawntype

/// A ghost with no mind is asked whether to spawn as its loaded character.
/obj/machinery/transhuman/autoresleever/proc/asks_loaded(datum/act/op/A)
	var/mob/observer/dead/user = A.actor
	return spawn_slots != 0 && !user.mind && !spawntype && ghost_spawns

/// Old attack_ghost.
/obj/machinery/transhuman/autoresleever/proc/autoresleever_interaction_ghost(datum/act/op/A)
	var/mob/observer/dead/user = A.actor
	. = OP_OK
	if(spawn_slots == 0)
		to_chat(user, span_warning("There are no more respawn slots."))
		return
	if(user.mind)
		if(user.mind.vore_death)
			if(ELAPSED(user, timeofdeath, CLOCK_WORLD) >= vore_respawn)
				autoresleeve(user)
			else
				to_chat(user, span_warning("You must wait [((vore_respawn - ELAPSED(user, timeofdeath, CLOCK_WORLD)) * 0.1) / 60] minutes to use \the [src]."))
				return
		else if(ELAPSED(user, timeofdeath, CLOCK_WORLD) >= respawn)
			autoresleeve(user)
		else
			to_chat(user, span_warning("You must wait [((respawn - ELAPSED(user, timeofdeath, CLOCK_WORLD)) * 0.1) /60] minutes to use \the [src]."))
			return
	else if(spawntype)
		var/_answer_k54 = A.step_value("k54")
		if(isnull(_answer_k54))
			return
		if(_answer_k54 == "Yes")
			autoresleeve(user)
	else if(ghost_spawns)
		var/_answer_k57 = A.step_value("k57")
		if(isnull(_answer_k57))
			return
		if(_answer_k57 == "Yes")
			autoresleeve(user)
	else
		to_chat(user, span_warning("You need to have been spawned in order to respawn here."))

/// Old attackby: let's not let people mess with this.
/obj/machinery/transhuman/autoresleever/proc/autoresleever_interaction_item(datum/act/op/A)
	return OP_PASS

/obj/machinery/transhuman/autoresleever/proc/autoresleeve(mob/observer/dead/ghost)
	if(has_stat(BROKEN | MAINT | EMPED)) // Let it still work when power is just off, it has it's own backup reserve or something.
		to_chat(ghost, span_warning("This machine is not functioning..."))
		return
	if(!isobserver(ghost))
		return
	var/mob/living/body = ghost.mind?.current
	if(ghost.mind && ghost.mind.current && ghost.mind.current.stat != DEAD && !(istype(body) && stat_value(body, STAT_SUSPENDED))) // A suspended body (kept for reforming) shouldn't block this.
		if(istype(ghost.mind.current.loc, /obj/item/mmi))
			var/_answer_k78 = rerun_ask(ghost, "k78", PROC_REF(autoresleeve), args, /datum/prompt/choice, question = "Your brain is still alive, using the auto-resleever will delete that brain. Are you sure?", title = "Delete Brain", choices = list("No","Yes"), buttons = TRUE)
			if(isnull(_answer_k78))
				return
			if(_answer_k78 != "Yes")
				return
			if(istype(ghost.mind.current.loc, /obj/item/mmi))
				spent(ghost.mind.current.loc)
		else
			to_chat(ghost, span_warning("Your body is still alive, you cannot be resleeved."))
			return

	var/client/ghost_client = ghost.client

	if(!is_alien_whitelisted(ghost.client, GLOB.all_species[ghost_client?.prefs?.read_preference(/datum/preference/choiced/species)]) && !check_rights(R_ADMIN, 0)) // Prevents a ghost ghosting in on a slot and spawning via a resleever with race they're not whitelisted for, getting around normal join restrictions.
		to_chat(ghost, span_warning("You are not whitelisted to spawn as this species!"))
		return

	if(!autoresleeve_species_allowed(ghost))
		return

	//Name matching is ugly but mind doesn't persist to look at.
	var/charjob
	var/datum/data/record/record_found
	record_found = find_general_record("name", ghost_client.prefs.read_preference(/datum/preference/name/real_name))

	//Found their record, they were spawned previously
	if(record_found)
		charjob = record_found.fields["real_rank"]
	else if(equip_body || ghost_spawns)
		charjob = default_job
	else
		to_chat(ghost, span_warning("It appears as though your loaded character has not been spawned this round, or has quit the round. If you died as a different character, please load them, and try again."))
		return

	//For logging later
	var/player_key = ghost_client.key
	var/picked_ckey = ghost_client.ckey
	var/picked_slot = ghost_client.prefs.default_slot

	var/spawnloc = get_turf(src)
	//Did we actually get a loc to spawn them?
	if(!spawnloc)
		to_chat(ghost, span_warning("Could not find a valid location to spawn your character."))
		return

	if(spawntype)
		autoresleeve_spawn_type(ghost, spawnloc, player_key, picked_ckey)
		return

	var/slot = ghost.client.prefs.default_slot
	var/_answer_k153 = rerun_ask(ghost, "k153", PROC_REF(autoresleeve), args, /datum/prompt/choice, question = "Would you like to be resleeved?", title = "Resleeve", choices = list("No","Yes"), buttons = TRUE)
	if(isnull(_answer_k153))
		return
	if(_answer_k153 != "Yes")
		if(ELAPSED(ghost, timeofdeath, CLOCK_WORLD) <= respawn) //We were given the option to resleeve due to an outside event, but closed the input box (be it by typing or otherwise) so we allow clicking the autosleever to revive.
			EXPIRY_SET(ghost, timeofdeath, -respawn, CLOCK_WORLD)
		return
	//This keeps people from dying in round, clicking the autoresleever, then swapping savefiles and clicking 'yes'
	if(slot != ghost.client.prefs.default_slot && (!equip_body || !ghost_spawns))
		var/turf/T = get_turf(src)
		to_chat(ghost, span_warning("It appears as though your loaded character has not been spawned this round, or has quit the round. If you died as a different character, please load them, and try again."))
		message_admins("[key_name_admin(ghost)] swapped savefiles while using the autosleever and tried to spawn as another character! [ADMIN_JMP(T)]")
		return
	var/mob/living/carbon/human/new_character = build_autoresleeved_character(ghost, ghost_client, spawnloc, player_key, picked_ckey, picked_slot)
	if(!new_character)
		return
	finish_autoresleeve(new_character, charjob)
	consume_spawn_slot()

/// Can `ghost`'s loaded species be resleeved here? Tells them why not.
/obj/machinery/transhuman/autoresleever/proc/autoresleeve_species_allowed(mob/observer/dead/ghost)
	var/datum/species/chosen_species
	var/pref_species = ghost.client.prefs.read_preference(/datum/preference/choiced/species)
	if(pref_species) // In case we somehow don't have a species set here.
		chosen_species = GLOB.all_species[pref_species]

	if(!chosen_species)
		to_chat(ghost, span_warning("No valid species is selected for resleeving!"))
		return FALSE

	if((chosen_species.spawn_flags & SPECIES_IS_WHITELISTED) || (chosen_species.spawn_flags & SPECIES_IS_RESTRICTED))
		to_chat(ghost, span_warning("This species cannot be resleeved!"))
		return FALSE

	return TRUE

/// A spawner resleever (spawntype set) hands the ghost a fresh `spawntype` instead of their character.
/obj/machinery/transhuman/autoresleever/proc/autoresleeve_spawn_type(mob/observer/dead/ghost, turf/spawnloc, player_key, picked_ckey)
	var/spawnthing = new spawntype(spawnloc)
	if(isliving(spawnthing))
		var/mob/living/L = spawnthing
		L.key = player_key
		L.ckey = picked_ckey
		log_admin("[L.ckey]'s has been spawned as [L] via \the [src].")
		message_admins("[L.ckey]'s has been spawned as [L] via \the [src].")
	else
		to_chat(ghost, span_warning("You can't play as a [spawnthing]..."))
		return
	consume_spawn_slot()

/// Uses one spawn slot; -1 is unlimited and 0 is exhausted.
/obj/machinery/transhuman/autoresleever/proc/consume_spawn_slot()
	if(spawn_slots > 0)
		spawn_slots--

/// Build the ghost's loaded character at `spawnloc`, move their mind in and restore antag roles.
/obj/machinery/transhuman/autoresleever/proc/build_autoresleeved_character(mob/observer/dead/ghost, client/ghost_client, turf/spawnloc, player_key, picked_ckey, picked_slot)
	var/mob/living/carbon/human/new_character = new(spawnloc)

	//We were able to spawn them, right?
	if(!new_character)
		to_chat(ghost, "Something went wrong and spawning failed.")
		return null

	//Write the appearance and whatnot out to the character
	ghost_client.prefs.copy_to(new_character)
	if(new_character.dna)
		new_character.dna.ResetUIFrom(new_character)
		new_character.sync_dna_traits(TRUE) // Traitgenes Sync traits to genetics if needed
		new_character.sync_organ_dna()
	new_character.sync_addictions() // These are addicitions our profile wants... May as well give them!
	new_character.initialize_vessel()
	if(ghost.mind)
		ghost.mind.transfer_to(new_character)

	new_character.key = player_key

	//Were they any particular special role? If so, copy.

	if(new_character.mind)
		new_character.mind.loaded_from_ckey = picked_ckey
		new_character.mind.loaded_from_slot = picked_slot
		var/datum/antagonist/antag_data = SSantag.get_antag_data(new_character.mind.special_role)
		if(antag_data)
			antag_data.add_antagonist(new_character.mind)
			antag_data.place_mob(new_character)
		if(new_character.mind.antag_holder)
			new_character.mind.antag_holder.apply_antags(new_character)

	apply_resleeve_languages(new_character, ghost, ghost_client)

	PUBLISH_LEGACY(new_character, /datum/notice/human_dna_finalized)
	return new_character

/// The character's whitelisted languages, custom language keys and preferred language.
/obj/machinery/transhuman/autoresleever/proc/apply_resleeve_languages(mob/living/carbon/human/new_character, mob/observer/dead/ghost, client/ghost_client)
	var/list/_ghost_alt_languages = ghost_client.prefs.read_preference(/datum/preference/alternate_languages)
	var/list/_ghost_lang_custom = ghost_client.prefs.read_preference(/datum/preference/language_custom_keys)
	for(var/lang in _ghost_alt_languages)
		var/datum/language/chosen_language = GLOB.all_languages[lang]
		if(chosen_language)
			if(is_lang_whitelisted(ghost,chosen_language) || (new_character.species && (chosen_language.name in new_character.species.secondary_langs)))
				new_character.add_language(lang)
	for(var/key in _ghost_lang_custom)
		if(_ghost_lang_custom[key])
			var/datum/language/keylang = GLOB.all_languages[_ghost_lang_custom[key]]
			if(keylang)
				new_character.language_keys[key] = keylang
	if(ghost_client.prefs.read_preference(/datum/preference/text/human/preferred_language)) // Do we have a preferred language?
		var/datum/language/def_lang = GLOB.all_languages[ghost_client.prefs.read_preference(/datum/preference/text/human/preferred_language)]
		if(def_lang)
			new_character.default_language = def_lang

/// Equip, log, implant a backup and announce a freshly resleeved character.
/obj/machinery/transhuman/autoresleever/proc/finish_autoresleeve(mob/living/carbon/human/new_character, charjob)
	//If desired, apply equipment.
	if(equip_body)
		if(charjob)
			SSjob.equip_rank(new_character, charjob, 1)
			new_character.mind.assigned_role = charjob
			new_character.mind.role_alt_title = SSjob.get_player_alt_title(new_character, charjob)

	//A redraw for good measure
	new_character.regenerate_icons()

	new_character.update_transform()

	log_admin("[new_character.ckey]'s character [new_character.real_name] has been auto-resleeved.")
	message_admins("[new_character.ckey]'s character [new_character.real_name] has been auto-resleeved.")

	var/obj/item/implant/backup/imp = new(src)

	if(imp.handle_implant(new_character,new_character.zone_sel.selecting))
		imp.post_implant(new_character)

	var/datum/transcore_db/db = SStranscore.db_by_mind_name(new_character.mind.name)
	if(db)
		var/datum/transhuman/mind_record/record = db.backed_up[new_character.mind.name]
		if(ELAPSED(record, last_notification, CLOCK_WORLD) < 30 MINUTES)
			GLOB.global_announcer.autosay("[new_character.name] has been resleeved by the automatic resleeving system.", "TransCore Oversight", HAS_SYNTHETIC_BIOLOGY(new_character) ? "Science" : "Medical")
		if(record.nif_path)
			after(new_character, 0, GLOBAL_PROC_REF(resleeve_restore_nif), with = list(new_character, record)) //Wait a moment for nif to do its thing if there is one

	if(!new_character.dna)
		CRASH("[new_character] just came out of an autosleever and has no DNA! Species: [new_character.species] as mob: [new_character.type]. NIF Status: [new_character.nif]")

/// Restores a resleeved body's backed-up NIF, then (a moment later, once a new NIF is in) its software.
/proc/resleeve_restore_nif(mob/living/carbon/human/new_character, datum/transhuman/mind_record/record)
	if(!new_character || !record)
		return
	var/obj/item/nif/nif = new_character.nif
	if(!nif)
		nif = new record.nif_path(new_character,null,record.nif_savedata)
	after(nif, 0, GLOBAL_PROC_REF(install_nif_software), with = list(nif, record.nif_software, record.nif_durability))

/// Installs `software` (NIFsoft types) in the NIF, then restores its durability if given.
/proc/install_nif_software(obj/item/nif/nif, list/software, durability)
	for(var/path in software)
		new path(nif)
	if(!isnull(durability))
		nif.durability = durability
