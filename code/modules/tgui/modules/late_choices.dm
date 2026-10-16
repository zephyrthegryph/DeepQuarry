/datum/tgui_module/late_choices
	name = "Late Join"

/datum/tgui_module/late_choices/tgui_status(mob/user, datum/tgui_state/state)
	if(!isnewplayer(user))
		return STATUS_CLOSE
	return STATUS_INTERACTIVE

/proc/get_user_job_priority(mob/user, datum/job/job)
	// was: GetJobDepartment(job, level) & job.flag bitwise check per level.
	. = 0
	if(!user?.client?.prefs)
		return
	switch(user.client.prefs.get_job_priority(job.title))
		if("high")
			. = 1
		if("med")
			. = 2
		if("low")
			. = 3

/proc/department_flag_to_name(department)
	switch(department)
		if(DEPARTMENT_COMMAND)
			. = "Command"
		if(DEPARTMENT_SECURITY)
			. = "Security"
		if(DEPARTMENT_ENGINEERING)
			. = "Engineering"
		if(DEPARTMENT_MEDICAL)
			. = "Medical"
		if(DEPARTMENT_RESEARCH)
			. = "Research"
		if(DEPARTMENT_CARGO)
			. = "Supply"
		if(DEPARTMENT_CIVILIAN)
			. = "Service"
		if(DEPARTMENT_PLANET)
			. = "Expedition"
		if(DEPARTMENT_SYNTHETIC)
			. = "Silicon"
		if(DEPARTMENT_TALON)
			. = "Offmap"
		else
			. = "Unknown"

/proc/character_old_enough_for_job(datum/preferences/prefs, datum/job/job)
	if(!job.minimum_character_age && !job.min_age_by_species)
		return TRUE

	var/min_age = job.get_min_age(prefs.read_preference(/datum/preference/choiced/species), prefs.read_preference(/datum/preference/organ_data)?[O_BRAIN])
	if(prefs.read_preference(/datum/preference/numeric/human/age) >= min_age)
		return TRUE
	return FALSE

CAPABILITIES(/datum/tgui_module/late_choices)
	interface("LateChoices")
	op("join", ui_act("join", arg("job", schema_text(4096))), needs(req(PROC_REF(ui_gate), silent = TRUE)), asks(/datum/prompt/choice, fields = list("question" = "Choose a Predator.", "title" = "Pred Spawnpoint", "choices" = computed(PROC_REF(late_join_pred_names)), "timeout" = 0), step = "pred", when = PROC_REF(late_join_asks_pred)), asks(/datum/prompt/choice, fields = list("question" = "Do you want a mind backup?", "title" = "Confirm", "choices" = list("Yes", "No"), "buttons" = TRUE, "timeout" = 0), step = "backup_vore", when = PROC_REF(late_join_asks_pred)), asks(/datum/prompt/choice, fields = list("question" = "Choose a Belly.", "title" = "Belly Spawnpoint", "choices" = computed(PROC_REF(late_join_pred_bellies)), "timeout" = 0), step = "belly", when = PROC_REF(late_join_asks_pred)), asks(/datum/prompt/choice, fields = list("question" = computed(PROC_REF(late_join_absorbed_question)), "title" = "Confirm", "choices" = list("Yes", "No"), "buttons" = TRUE, "timeout" = 0), step = "absorbed", when = PROC_REF(late_join_asks_absorbed)), asks(/datum/prompt/choice, fields = list("question" = computed(PROC_REF(late_join_go_on_question)), "title" = "Confirm", "choices" = list("Yes", "No"), "buttons" = TRUE, "timeout" = 0), step = "go_on", when = PROC_REF(late_join_asks_go_on)), asks(/datum/prompt/choice, fields = list("question" = "Choose a Prey to spawn nom.", "title" = "Prey Spawnpoint", "choices" = computed(PROC_REF(late_join_prey_names)), "timeout" = 0), step = "prey", when = PROC_REF(late_join_asks_prey)), asks(/datum/prompt/choice, fields = list("question" = "Choose your Belly.", "title" = "Belly Spawnpoint", "choices" = computed(PROC_REF(late_join_own_bellies)), "timeout" = 0), step = "belly_pred", when = PROC_REF(late_join_asks_prey)), asks(/datum/prompt/choice, fields = list("question" = "Do you want to instantly absorb them?", "title" = "Confirm", "choices" = list("Yes", "No"), "buttons" = TRUE, "timeout" = 0), step = "absorb", when = PROC_REF(late_join_asks_prey)), asks(/datum/prompt/choice, fields = list("question" = "Do you want a mind backup?", "title" = "Confirm", "choices" = list("Yes", "No"), "buttons" = TRUE, "timeout" = 0), step = "backup_item", when = PROC_REF(late_join_asks_item)), asks(/datum/prompt/choice, fields = list("question" = "Choose an Item to spawn as.", "title" = "Item TF Spawnpoint", "choices" = computed(PROC_REF(late_join_item_names)), "timeout" = 0), step = "item", when = PROC_REF(late_join_asks_item)), asks(/datum/prompt/choice, fields = list("question" = computed(PROC_REF(late_join_unheld_question)), "title" = "Confirm", "choices" = list("No", "Yes"), "buttons" = TRUE, "timeout" = 0), step = "unheld", when = PROC_REF(late_join_asks_unheld)), asks(/datum/prompt/choice, fields = list("question" = "Do you want to spawn with your slot's vore organs and prefs?", "title" = "Confirm", "choices" = list("No", "Yes"), "buttons" = TRUE, "timeout" = 0), step = "vorgans", when = PROC_REF(late_join_asks_vorgans)), then(PROC_REF(ui_act_join)))

/datum/tgui_module/late_choices/ui_data(datum/act/eval/A)
	var/mob/new_player/user = A.actor
	var/list/data = list()

	var/name = user.client.prefs.read_preference(/datum/preference/toggle/human/name_is_always_random) ? "friend" : user.client.prefs.read_preference(/datum/preference/name/real_name)

	data["name"] = name
	data["duration"] = roundduration2text()

	if(SSemergency_shuttle?.going_to_centcom())
		data["evac"] = "Gone"
	else if(SSemergency_shuttle?.online())
		if(emergency_shuttle_evac())
			data["evac"] = "Emergency"
		else
			data["evac"] = "Crew Transfer"
	else
		data["evac"] = "None"

	var/list/jobs = list()

	for(var/datum/job/job in job_occupations())
		if(job && user.IsJobAvailable(job.title))
			// Check for jobs with minimum age requirements
			if(!character_old_enough_for_job(user.client.prefs, job))
				continue

			// Check species job bans... (Only used for shadekin)
			if(job.is_species_banned(user.client.prefs.read_preference(/datum/preference/choiced/species), user.client.prefs.read_preference(/datum/preference/organ_data)?[O_BRAIN]))
				continue

			var/active = 0
			// Only players with the job assigned and AFK for less than 10 minutes count as active
			for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
				if(M.mind?.assigned_role == job.title && M.client?.inactivity <= 10 MINUTES)
					active++

			// Figure out departments
			var/list/departments = list()

			for(var/department in job.departments)
				departments += department_flag_to_name(department)

			UNTYPED_LIST_ADD(jobs, list(
				"title" = job.title,
				"priority" = get_user_job_priority(user, job),
				"departments" = departments,
				"current_positions" = job.current_positions,
				"active" = active,
				"offmap" = job.offmap_spawn,
			))

	data["jobs"] = jobs

	return data

/// Only somebody still in the lobby joins (silently: anyone else is just not answered).
/datum/tgui_module/late_choices/proc/ui_gate(datum/act/op/A)
	return (isnewplayer(A.actor)) ? null : /datum/msg/req_silent

/datum/tgui_module/late_choices/proc/ui_act_join(datum/act/op/A, job_arg)
	var/mob/user = A.actor
	var/mob/new_player/new_user = user
	var/job = job_arg

	if(!CONFIG_GET(flag/enter_allowed))
		to_chat(new_user, span_notice("There is an administrative lock on entering the game!"))
		return
	else if(SSticker && ticker_mode() && ticker_mode().explosion_in_progress)
		to_chat(new_user, span_danger("The station is currently exploding. Joining would go poorly."))
		return

	var/pref_species = new_user.client.prefs.read_preference(/datum/preference/choiced/species)
	var/datum/species/S = GLOB.all_species[pref_species]
	if(!is_alien_whitelisted(new_user.client, S))
		tgui_alert_async(new_user, "You are currently not whitelisted to play [pref_species].")
		return 0

	if(!(S.spawn_flags & SPECIES_CAN_JOIN))
		tgui_alert_async(new_user,"Your current species, [pref_species], is not available for play on the station.")
		return 0

	new_user.AttemptLateSpawn(job, user, late_join_answers(A))

// ---- the join op's questions: the vore and item spawnpoints ask the joiner before the join runs (SSjob.late_spawn() reads the answers) ----

/// Question gate: the join would go ahead (nothing refuses it yet), so the spawnpoint's questions are worth asking. The refusals themselves
/// (and their messages) come from ui_act_join() and do_late_spawn() when the op's handler runs.
/datum/tgui_module/late_choices/proc/late_join_askable(datum/act/op/A)
	var/mob/new_player/user = A.actor
	if(!istype(user) || QDELETED(user) || !user.client || user.client.login_pending || user.spawning)
		return FALSE
	if(!SSticker || ticker_current_state() != GAME_STATE_PLAYING)
		return FALSE
	if(!CONFIG_GET(flag/enter_allowed))
		return FALSE
	if(SSticker && ticker_mode() && ticker_mode().explosion_in_progress)
		return FALSE
	var/pref_species = user.client.prefs.read_preference(/datum/preference/choiced/species)
	var/datum/species/S = GLOB.all_species[pref_species]
	if(!read_once(is_alien_whitelisted(user.client, S)) || !(S.spawn_flags & SPECIES_CAN_JOIN))
		return FALSE
	var/rank = A.arg("job")
	if(!read_once(user.IsJobAvailable(rank)))
		return FALSE
	return read_once(user.spawn_checks_vr(rank, TRUE))

/// The spawnpoint the joiner chose.
/datum/tgui_module/late_choices/proc/late_join_spawnpoint(datum/act/op/A)
	var/mob/new_player/user = A.actor
	return user.client.prefs.read_preference(/datum/preference/choiced/living/spawnpoint)

/// The preds the joiner could spawn into, as the names the question shows.
/datum/tgui_module/late_choices/proc/late_join_pred_names(datum/act/op/A)
	return SSjob.vorespawn_names(read_once(SSjob.vorespawn_preds()))

/// The pred the joiner picked, or null.
/datum/tgui_module/late_choices/proc/late_join_pred(datum/act/op/A)
	var/picked = A.step_value("pred")
	if(isnull(picked))
		return null
	var/list/preds = read_once(SSjob.vorespawn_preds())
	var/index = SSjob.vorespawn_names(preds).Find(picked)
	return index ? preds[index] : null

/// The bellies of the picked pred the joiner may spawn into.
/datum/tgui_module/late_choices/proc/late_join_pred_bellies(datum/act/op/A)
	var/mob/living/pred = late_join_pred(A)
	var/mob/new_player/user = A.actor
	return pred ? SSjob.vorespawn_bellies(pred, user.client.ckey) : list()

/// The belly the joiner picked, or null.
/datum/tgui_module/late_choices/proc/late_join_belly(datum/act/op/A)
	var/obj/belly/picked = A.step_value("belly")
	if(!istype(picked))
		return null
	return (picked in late_join_pred_bellies(A)) ? picked : null

/// Question gate: the joiner spawns as prey and there are preds to ask.
/datum/tgui_module/late_choices/proc/late_join_asks_pred(datum/act/op/A)
	if(!late_join_askable(A) || late_join_spawnpoint(A) != "Vorespawn - Prey")
		return FALSE
	return length(read_once(SSjob.vorespawn_preds())) > 0

/// Question gate: the picked belly can start the joiner absorbed, and the joiner chooses.
/datum/tgui_module/late_choices/proc/late_join_asks_absorbed(datum/act/op/A)
	if(!late_join_asks_pred(A))
		return FALSE
	var/obj/belly/gut = late_join_belly(A)
	return gut && (gut.vorespawn_absorbed & VS_FLAG_ABSORB_YES) && (gut.vorespawn_absorbed & VS_FLAG_ABSORB_PREY)

/// Question gate: the picked belly starts the joiner absorbed, and the joiner confirms.
/datum/tgui_module/late_choices/proc/late_join_asks_go_on(datum/act/op/A)
	if(!late_join_asks_pred(A))
		return FALSE
	var/obj/belly/gut = late_join_belly(A)
	return gut && (gut.vorespawn_absorbed & VS_FLAG_ABSORB_YES) && !(gut.vorespawn_absorbed & VS_FLAG_ABSORB_PREY)

/datum/tgui_module/late_choices/proc/late_join_absorbed_question(datum/act/op/A)
	return "Do you want to start absorbed into [late_join_pred(A)]'s [late_join_belly(A)]?"

/datum/tgui_module/late_choices/proc/late_join_go_on_question(datum/act/op/A)
	return "[late_join_pred(A)]'s [late_join_belly(A)] will start with you absorbed. Continue?"

/// The preys the joiner could spawn onto, as the names the question shows.
/datum/tgui_module/late_choices/proc/late_join_prey_names(datum/act/op/A)
	return SSjob.vorespawn_names(read_once(SSjob.vorespawn_preys()))

/// The bellies in the joiner's own vore prefs.
/datum/tgui_module/late_choices/proc/late_join_own_bellies(datum/act/op/A)
	var/mob/new_player/user = A.actor
	return SSjob.vorespawn_own_belly_names(user.client)

/// Question gate: the joiner spawns as a pred and there are preys to ask.
/datum/tgui_module/late_choices/proc/late_join_asks_prey(datum/act/op/A)
	if(!late_join_askable(A) || late_join_spawnpoint(A) != "Vorespawn - Pred")
		return FALSE
	return length(read_once(SSjob.vorespawn_preys())) > 0

/// The item spawnpoints the joiner may spawn as (SSjob.itemspawn_options()).
/datum/tgui_module/late_choices/proc/late_join_options(datum/act/op/A)
	var/mob/new_player/user = A.actor
	return SSjob.itemspawn_options(user.client)

/datum/tgui_module/late_choices/proc/late_join_item_names(datum/act/op/A)
	var/list/options = late_join_options(A)
	return options["names"]

/// The item spawnpoint the joiner picked: list("item" = it, "carrier" = who holds it), or null.
/datum/tgui_module/late_choices/proc/late_join_item(datum/act/op/A)
	var/picked = A.step_value("item")
	if(isnull(picked))
		return null
	var/list/options = late_join_options(A)
	var/list/names = options["names"]
	var/index = names.Find(picked)
	if(!index)
		return null
	var/list/items = options["items"]
	var/list/carriers = options["carriers"]
	return list("item" = items[index], "carrier" = carriers[index])

/// Question gate: the joiner spawns as an item and there are items to pick from.
/datum/tgui_module/late_choices/proc/late_join_asks_item(datum/act/op/A)
	if(!late_join_askable(A) || late_join_spawnpoint(A) != "Item TF spawn")
		return FALSE
	var/list/options = late_join_options(A)
	return LAZYLEN(options["items"]) > 0

/// Question gate: the picked item is held by nobody, and the joiner confirms spawning as it.
/datum/tgui_module/late_choices/proc/late_join_asks_unheld(datum/act/op/A)
	if(!late_join_asks_item(A))
		return FALSE
	var/list/picked = late_join_item(A)
	return picked && !istype(picked["carrier"], /mob/living)

/datum/tgui_module/late_choices/proc/late_join_unheld_question(datum/act/op/A)
	var/list/picked = late_join_item(A)
	var/obj/item/item = picked?["item"]
	return "\The [item?.name] is currently not in any character's possession! Do you still want to spawn as it?"

/// Question gate: the picked item is a capture crystal with a mob in it, the joiner may spawn as it (an unheld one only after confirming), and chooses the organs.
/datum/tgui_module/late_choices/proc/late_join_asks_vorgans(datum/act/op/A)
	if(!late_join_asks_item(A))
		return FALSE
	var/list/picked = late_join_item(A)
	if(!picked)
		return FALSE
	var/obj/item/capture_crystal/cryst = picked["item"]
	if(!istype(cryst) || !cryst.spawn_mob_type)
		return FALSE
	if(!istype(picked["carrier"], /mob/living) && A.step_value("unheld") != "Yes")
		return FALSE
	return TRUE

/// The join op's answers as SSjob.late_spawn() reads them: step name -> answer (the belly picked by its name, which stands for it while the
/// pred or prey is asked).
/datum/tgui_module/late_choices/proc/late_join_answers(datum/act/op/A)
	var/list/answers = list()
	answers["pred"] = A.step_value("pred")
	answers["backup_vore"] = A.step_value("backup_vore")
	var/obj/belly/gut = A.step_value("belly")
	answers["belly"] = istype(gut) ? gut.name : null
	answers["absorbed"] = A.step_value("absorbed")
	answers["go_on"] = A.step_value("go_on")
	answers["prey"] = A.step_value("prey")
	answers["belly_pred"] = A.step_value("belly_pred")
	answers["absorb"] = A.step_value("absorb")
	answers["backup_item"] = A.step_value("backup_item")
	answers["item"] = A.step_value("item")
	answers["unheld"] = A.step_value("unheld")
	answers["vorgans"] = A.step_value("vorgans")
	return answers
