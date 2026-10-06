//Datum that's initialized on first calling the client procs. It's stored in /client
//We keep a distinct names/refs list in an effort to make things speedy, and for easy checking if something is on our list.
//We manually add to list element with procs to avoid dealing with clunky global lists that might not be relevant
//and for ability to narrate from long range.
/datum/entity_narrate
	var/list/entity_names
	/// unique name -> /datum/entity_narrate_entry (owned), whose target is a relation view. Read with tracked(name).
	var/list/entity_refs


	//TGUI Helper Vars
	tgui_id = "EntityNarrate"
	var/tgui_selection_mode = 0 //0 for single entity, 1 for multi entity
	var/tgui_selected_name = "" //String for single selection in-game name
	var/tgui_selected_type = "" //String for single selection type
	var/tgui_selected_id = ""   //String to retrieve ref from entity_refs
	var/atom/tgui_selected_refs //the selected object (a relation view)
	var/list/tgui_selected_id_multi //List of strings containing mob ids for multi selection
	var/tgui_narrate_mode = 0 //0 for speak, 1 for emote
	var/tgui_narrate_privacy = 0 //0 for loud, 1 for subtle
	COOLDOWN_DECLARE(tgui_message_cooldown) // int to avoid spam

CAPABILITIES(/datum/entity_narrate)
	owns_many(nameof(entity_refs))
	interface(null, title = "Entity Narration", rights = R_FUN, window_var = nameof(tgui_id))
	op("change_mode_multi", ui_act("change_mode_multi"), then(PROC_REF(ui_act_change_mode_multi)))
	op("change_mode_privacy", ui_act("change_mode_privacy"), then(PROC_REF(ui_act_change_mode_privacy)))
	op("change_mode_narration", ui_act("change_mode_narration"), then(PROC_REF(ui_act_change_mode_narration)))
	op("select_entity", ui_act("select_entity", arg("id_selected", schema_text(4096))), then(PROC_REF(ui_act_select_entity)))
	op("narrate", ui_act("narrate", arg("message", schema_text(4096))), then(PROC_REF(ui_act_narrate)))




//Appears as a right click verb on any obj and mob within view range.
//when not right clicking we get a list to pick from in aforementioned view range.
ADMIN_VERB_AND_CONTEXT_MENU(add_mob_for_narration, R_FUN, "Narrate Entity (Add ref)", "Saves a reference of target mob to be called when narrating.", "Fun.Narrate", E as obj|mob|turf in orange(world.view))
	//Making sure we got the list datum on our client.
	if(!user.entity_narrate_holder)
		user.entity_narrate_holder = new /datum/entity_narrate()
	if(!istype(user.entity_narrate_holder, /datum/entity_narrate))
		return
	//Since we extended to include all atoms, we're shutting things down with a guard clause for ghosts
	if(istype(E, /mob/observer))
		to_chat(user, span_notice("Ghosts shouldn't be narrated! If you want a ghost, make it a subtype of mob/living!"))
		return
	//We require a static mob/living type to check for .client and also later on, to use the unique .say mechanics for stuttering and language
	if(isliving(E))
		var/mob/living/L = E
		if(L.client)
			to_chat(user, span_notice("[L.name] is a player. All attempts to speak through them \
			gets logged in case of abuse."))
			log_and_message_admins("has added [L.ckey]'s mob to their entity narrate list", user)
			return
	if(istype(E, /atom))
		var/atom/target = E
		open_request(src, /datum/prompt/text/admin_narrate_add, PROC_REF(entity_name_answered), answerer = user.mob, subject = target, default = target.name)

/datum/prompt/text/admin_narrate_add
	rights = R_FUN
	timeout = 0
	recheck_on_open = TRUE
	encode = TRUE
	max_len = MAX_MESSAGE_LEN
	title = "tracker"
	question = "Please give the entity a unique name to track internally. This doesn't override how it appears in game"

/datum/prompt/text/admin_narrate_add/recheck_extra()
	if(QDELETED(answerer) || !answerer.client || QDELETED(subject))
		return "gone"
	var/client/user = answerer.client
	if(user.entity_narrate_holder && !istype(user.entity_narrate_holder, /datum/entity_narrate))
		return "holder"
	if(istype(subject, /mob/observer))
		return "ghost"
	if(isliving(subject))
		var/mob/living/L = subject
		if(L.client)
			return "player"
	var/datum/entity_narrate/holder = user.entity_narrate_holder
	if(!isnull(value) && holder && (value in holder.entity_names))
		return "duplicate"

/datum/admin_verb/add_mob_for_narration/proc/entity_name_answered(datum/act/request/context)
	if(isnull(context.request.value) || QDELETED(context.request.answerer) || !context.request.answerer.client || QDELETED(context.request.subject))
		return
	if(!context.answer && !(context.request.last_error in list("holder", "ghost", "player", "duplicate")))
		return
	apply_entity_name(context)

/datum/admin_verb/add_mob_for_narration/proc/apply_entity_name(datum/act/request/context)
	var/client/user = context.request.answerer.client
	// The original verb replay recreates a missing holder before a target denial.
	if(!user.entity_narrate_holder)
		user.entity_narrate_holder = new /datum/entity_narrate()
	var/datum/entity_narrate/holder = user.entity_narrate_holder
	var/atom/target = context.request.subject
	var/unique_name = context.request.value
	if(!context.answer)
		switch(context.request.last_error)
			if("ghost")
				to_chat(user, span_notice("Ghosts shouldn't be narrated! If you want a ghost, make it a subtype of mob/living!"))
			if("player")
				var/mob/living/L = target
				to_chat(user, span_notice("[L.name] is a player. All attempts to speak through them \
				gets logged in case of abuse."))
				log_and_message_admins("has added [L.ckey]'s mob to their entity narrate list", user)
			if("duplicate")
				to_chat(user, span_notice("[unique_name] is not unique! Pick another!"))
		return
	LAZYADD(holder.entity_names, unique_name)
	holder.track(unique_name, target)
	log_and_message_admins("added [target.name] for their personal list to narrate", user) //Logging here to avoid spam, while still safeguarding abuse

//Proc for keeping our ref list relevant, deleting mobs that are no longer relevant for our event
ADMIN_VERB(remove_mob_for_narration, R_FUN, "Narrate Entity (Remove ref)", "Remove mobs you're no longer narrating from your list for easier work.", ADMIN_CATEGORY_FUN_NARRATE)
	var/datum/entity_narrate/holder = current_holder(user)
	if(!holder)
		return
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_narrate_remove, PROC_REF(removal_selected), answerer = answerer, choices = (holder.entity_names || list()) + "Clear All")

/datum/admin_verb/remove_mob_for_narration/proc/current_holder(client/user)
	if(!user.entity_narrate_holder)
		user.entity_narrate_holder = new /datum/entity_narrate()
		to_chat(user, "No references were added yet! First add references!")
		return
	if(!istype(user.entity_narrate_holder, /datum/entity_narrate))
		return
	return user.entity_narrate_holder


/datum/admin_verb/remove_mob_for_narration/proc/removal_selected(datum/act/request/context)
	if(!context.answer)
		return
	apply_selected_removal(context)

/datum/admin_verb/remove_mob_for_narration/proc/apply_selected_removal(datum/act/request/context)
	var/client/user = context.request.answerer.client
	var/datum/entity_narrate/holder = current_holder(user)
	if(!holder)
		return
	var/removekey = context.request.value
	if(removekey == "Clear All")
		open_request(src, /datum/prompt/choice/admin_narrate_clear, PROC_REF(clear_selected), answerer = user.mob)
	else if(removekey)
		holder.untrack(removekey)
		LAZYREMOVE(holder.entity_names, removekey)

/datum/admin_verb/remove_mob_for_narration/proc/clear_selected(datum/act/request/context)
	if(!context.answer)
		return
	apply_clear(context)

/datum/admin_verb/remove_mob_for_narration/proc/apply_clear(datum/act/request/context)
	var/datum/entity_narrate/holder = current_holder(context.request.answerer.client)
	if(!holder || context.request.value != "Yes")
		return
	holder.entity_names = list()
	own_clear(holder, nameof(/datum/entity_narrate::entity_refs), OWN_DELETE)

//Planned to have TGUI functionality
//For now brings up a list of all entities on our reference list and gives us the option to choose what we wanna do
//using TGUI/Byond list/alert inputs
//Does not actually interact with the game world, it passes user input to narrate_mob_args(name, mode, message) after sanitizing
ADMIN_VERB(narrate_mob, R_FUN, "Narrate Entity (Interface)", "Send either a visible or audiable message through your chosen entities using an interface.", ADMIN_CATEGORY_FUN_NARRATE)
	// Only this verb's actual ended native request supplies replay answers.
	var/list/replay_answers = list()
	if(length(args) >= 2)
		var/datum/request/resumed = args[2]
		if((istype(resumed, /datum/prompt/choice/admin_narrate_interface_replay) || istype(resumed, /datum/prompt/text/admin_narrate_interface_replay)) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(narrate_mob_replay_answered))
			replay_answers = resumed.captured.Copy()
			replay_answers[resumed.step_name] = resumed.value
	if(!user.entity_narrate_holder)
		user.entity_narrate_holder = new /datum/entity_narrate()
		to_chat(user, "No references were added yet! First add references!")
		return
	if(!istype(user.entity_narrate_holder, /datum/entity_narrate))
		return
	var/datum/entity_narrate/holder = user.entity_narrate_holder

	//Obtaining and sanitizing arguments for the actual proc
	var/choices = (holder.entity_names || list()) + "Open TGUI"
	if(!("a5" in replay_answers))
		open_request(src, /datum/prompt/choice/admin_narrate_interface_replay, PROC_REF(narrate_mob_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a5", question = "Choose which mob to narrate", title = "Narrate mob", choices = choices)
		return
	var/which_entity = replay_answers["a5"]
	if(isnull(which_entity))
		return
	if(!which_entity) return
	if(which_entity == "Open TGUI")
		holder.tgui_interact(user.mob)
	else
		if(!("a6" in replay_answers))
			open_request(src, /datum/prompt/choice/admin_narrate_interface_replay, PROC_REF(narrate_mob_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a6", buttons = TRUE, question = "Speak or emote?", title = "mode", choices = list("Speak", "Emote", "Cancel"))
			return
		var/mode = replay_answers["a6"]
		if(isnull(mode))
			return
		if(!mode || mode == "Cancel") return
		if(!("a7" in replay_answers))
			open_request(src, /datum/prompt/text/admin_narrate_interface_replay, PROC_REF(narrate_mob_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a7", question = "Input what you want [which_entity] to [mode]", title = "narrate", multiline = TRUE, max_len = MAX_TGUI_INPUT)
			return
		var/message = replay_answers["a7"]
		if(isnull(message))
			return
		if(message)
			SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/narrate_mob_args, which_entity, mode, message)

//The actual logic of the verb. Called by narrate_mob() when used.
ADMIN_VERB(narrate_mob_args, R_FUN, "Narrate Entity", "Narrate entities using positional arguments. Name should be as saved in ref list, mode should be Speak or Emote, follow with message.", "Fun.Narrate", name as text, mode as text, message as text)
	// Only this verb's actual ended native request supplies replay answers.
	var/list/replay_answers = list()
	var/is_native_replay = FALSE
	if(length(args) >= 5)
		var/datum/request/resumed = args[5]
		if((istype(resumed, /datum/prompt/text/admin_narrate_args_replay)) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(narrate_mob_args_replay_answered) && name == resumed.captured["original_name"] && mode == resumed.captured["original_mode"] && message == resumed.captured["original_message"])
			is_native_replay = TRUE
			replay_answers = resumed.captured.Copy()
			replay_answers[resumed.step_name] = resumed.value
	if(!user.entity_narrate_holder)
		user.entity_narrate_holder = new /datum/entity_narrate()
		to_chat(user, "No references were added yet! First add references!")
		return
	if(!istype(user.entity_narrate_holder, /datum/entity_narrate))
		return
	var/datum/entity_narrate/holder = user.entity_narrate_holder

	//Sanitizing args
	name = sanitize(name)
	mode = sanitize(mode)

	if(!(mode in list("Speak", "Emote")))
		to_chat(user, span_notice("Valid modes are 'Speak' and 'Emote'."))
		return
	if(!LAZYACCESS(holder.entity_refs, name))
		to_chat(user, span_notice("[name] not in saved references!"))
		return

	//Separate definition for mob/living and /obj due to .say() code allowing us to engage with languages, stuttering etc
	//We also need this so we can check for .client
	var/selection = holder.tracked(name)
	if(!selection)
		to_chat(user, span_notice("[name] has invalid reference, deleting"))
		LAZYREMOVE(holder.entity_names, name)
		holder.untrack(name)
		return
	if(isliving(selection))
		var/mob/living/our_entity = selection
		if(our_entity.client) //Making sure we can't speak for players
			if(!is_native_replay) // Once: the message prompt re-runs this.
				log_and_message_admins("used entity-narrate to speak through [our_entity.ckey]'s mob", user)
		if(!message)
			if(!("a8" in replay_answers))
				replay_answers["original_name"] = args[2]
				replay_answers["original_mode"] = args[3]
				replay_answers["original_message"] = args[4]
				open_request(src, /datum/prompt/text/admin_narrate_args_replay, PROC_REF(narrate_mob_args_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a8", question = "Input what you want [our_entity] to [mode]", title = "narrate", encode = FALSE)
				return
			var/_answer_a8 = replay_answers["a8"]
			if(isnull(_answer_a8))
				return
			message = _answer_a8 //say/emote sanitize already
		if(message && mode == "Speak")
			our_entity.say(message)
		else if(message && mode == "Emote")
			our_entity.custom_emote(VISIBLE_MESSAGE, message)
		else
			return

	//This does cost us some code duplication, but I think it's worth it.
	//furthermore, objs/turfs require the user to specify the verb when speaking, otherwise it looks like an emote.
	else if(istype(selection, /atom))
		var/atom/our_entity = selection
		if(!message)
			if(!("a9" in replay_answers))
				replay_answers["original_name"] = args[2]
				replay_answers["original_mode"] = args[3]
				replay_answers["original_message"] = args[4]
				open_request(src, /datum/prompt/text/admin_narrate_args_replay, PROC_REF(narrate_mob_args_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a9", question = "Input what you want [our_entity] to [mode]", title = "narrate")
				return
			var/_answer_a9 = replay_answers["a9"]
			if(isnull(_answer_a9))
				return
			message = _answer_a9
		message = encode_html_emphasis(sanitize(message))
		if(message && mode == "Speak")
			our_entity.audible_message(span_bold("[our_entity.name]") + " [message]")
		else if(message && mode == "Emote")
			act_message(our_entity, null, others = span_bold("%U%") + " [MSG_LITERAL(message)]")
		else
			return


/datum/entity_narrate/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["mode_select"] = tgui_narrate_mode
	data["privacy_select"] = tgui_narrate_privacy
	data["selected_id"] = tgui_selected_id
	data["selected_name"] = tgui_selected_name
	data["selected_type"] = tgui_selected_type
	data["selection_mode"] = tgui_selection_mode
	var/list/merged_1 = ui_data_datum_entity_narrate(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /datum/entity_narrate's window data.
/datum/entity_narrate/proc/ui_data_datum_entity_narrate(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["multi_id_selection"] = (tgui_selected_id_multi || list())
	data["number_mob_selected"] = LAZYLEN(tgui_selected_id_multi)
	data["entity_names"] = (entity_names || list())

	return data

/datum/entity_narrate/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(.)	return FALSE
	if(!check_rights_for(user.client, R_FUN)) return FALSE
	return TRUE

/datum/entity_narrate/proc/ui_act_change_mode_multi(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	tgui_selection_mode = !tgui_selection_mode
	//Clearing selections after switching mode
	tgui_selected_id_multi = list()
	tgui_selected_id = ""
	tgui_selected_type = ""
	tgui_selected_name = ""
	rel_clear(src, nameof(/datum/entity_narrate::tgui_selected_refs))
	return TRUE

/datum/entity_narrate/proc/ui_act_change_mode_privacy(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	tgui_narrate_privacy = !tgui_narrate_privacy
	return TRUE

/datum/entity_narrate/proc/ui_act_change_mode_narration(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	tgui_narrate_mode = !tgui_narrate_mode
	return TRUE

/datum/entity_narrate/proc/ui_act_select_entity(datum/act/op/A, id_selected)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(tgui_selection_mode)
		if(id_selected in tgui_selected_id_multi)
			LAZYREMOVE(tgui_selected_id_multi, id_selected)
		else
			LAZYADD(tgui_selected_id_multi, id_selected)
	else
		if(id_selected in tgui_selected_id_multi)
			LAZYREMOVE(tgui_selected_id_multi, id_selected)
			tgui_selected_id = ""
			tgui_selected_type = ""
			tgui_selected_name = ""
			rel_clear(src, nameof(/datum/entity_narrate::tgui_selected_refs))
		else
			tgui_selected_id_multi = list() //Using the same var for ease of implementation. Thus, we must reset to empty each time.
			LAZYADD(tgui_selected_id_multi, id_selected)
			tgui_selected_id = id_selected
			var/atom/picked = tracked(tgui_selected_id)
			if(picked)
				rel_set(src, nameof(/datum/entity_narrate::tgui_selected_refs), picked)
			else
				rel_clear(src, nameof(/datum/entity_narrate::tgui_selected_refs))
			if(!tgui_selected_refs)
				to_chat(user, span_notice("[tgui_selected_id] has invalid reference, deleting"))
				LAZYREMOVE(entity_names, tgui_selected_id)
				untrack(tgui_selected_id)
				tgui_selected_id = ""
				tgui_selected_type = ""
				tgui_selected_name = ""
				rel_clear(src, nameof(/datum/entity_narrate::tgui_selected_refs))
			if(isliving(tgui_selected_refs))
				var/mob/living/L = tgui_selected_refs
				if(L.client)
					tgui_selected_type = "!!!!PLAYER!!!!"
					tgui_selected_name = L.name
				else
					tgui_selected_type = L.type
					tgui_selected_name = L.name
			else if(istype(tgui_selected_refs, /atom))
				var/atom/A2 = tgui_selected_refs
				tgui_selected_type = A2.type
				tgui_selected_name = A2.name
	return TRUE

/datum/entity_narrate/proc/ui_act_narrate(datum/act/op/A, message_arg)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!COOLDOWN_FINISHED(src, tgui_message_cooldown))
		to_chat(user, span_notice("You can't messages that quickly! Wait at least half a second"))
	else
		to_chat(user, span_notice("Message successfully sent!"))
		COOLDOWN_START(src, tgui_message_cooldown, 0.5 SECONDS)
		var/message = message_arg //Sanitizing before speaking it
		if(tgui_selection_mode)
			for(var/entity in tgui_selected_id_multi)
				var/ref = tracked(entity)
				if(!ref)
					to_chat(user, span_notice("[entity] has invalid reference, deleting"))
					LAZYREMOVE(entity_names, entity)
					untrack(entity)
					LAZYREMOVE(tgui_selected_id_multi, entity)
					continue
				if(isliving(ref))
					var/mob/living/L = ref
					if(L.client)
						log_and_message_admins("used entity-narrate to speak through [L.ckey]'s mob", user)
					narrate_tgui_mob(L, message)
				else if(istype(ref, /atom))
					var/atom/A2 = ref
					narrate_tgui_atom(A2, message)
		else
			var/ref = tracked(tgui_selected_id)
			if(!ref)
				to_chat(user, span_notice("[tgui_selected_id] has invalid reference, deleting"))
				LAZYREMOVE(entity_names, tgui_selected_id)
				untrack(tgui_selected_id)
				tgui_selected_id = ""
				tgui_selected_type = ""
				tgui_selected_name = ""
				rel_clear(src, nameof(/datum/entity_narrate::tgui_selected_refs))
				return TRUE
			if(isliving(ref))
				var/mob/living/L = ref
				if(L.client)
					log_and_message_admins("used entity-narrate to speak through [L.ckey]'s mob", user)
				narrate_tgui_mob(L, message)
			else if(istype(ref, /atom))
				var/atom/A2 = ref
				narrate_tgui_atom(A2, message)
	return TRUE

/datum/entity_narrate/proc/narrate_tgui_mob(mob/living/L, message as text)
	//say and custom_emote sanitize it themselves, not sanitizing here to avoid double encoding.
	if(tgui_narrate_mode && tgui_narrate_privacy)
		L.custom_emote_vr(m_type = VISIBLE_MESSAGE, message = message)
	else if(tgui_narrate_mode && !tgui_narrate_privacy)
		L.custom_emote(VISIBLE_MESSAGE, message)
	else if(!tgui_narrate_mode && tgui_narrate_privacy)
		L.say(message, whispering = 1)
	else if(!tgui_narrate_mode && !tgui_narrate_privacy)
		L.say(message)

/datum/entity_narrate/proc/narrate_tgui_atom(atom/A, message as text)
	message = encode_html_emphasis(sanitize(message))
	if(tgui_narrate_mode && tgui_narrate_privacy)
		A.visible_message(span_italics(span_bold("\The [A.name]") + " [message]"), range = 1)
	else if(tgui_narrate_mode && !tgui_narrate_privacy)
		A.visible_message(span_bold("\The [A.name]") + " [message]",)
	else if(!tgui_narrate_mode && tgui_narrate_privacy)
		A.audible_message(span_italics(span_bold("\The [A.name]") + " [message]"), hearing_distance = 1)
	else if(!tgui_narrate_mode && !tgui_narrate_privacy)
		A.audible_message(span_bold("\The [A.name]") + " [message]")

/// One tracked narration entity: its target is a relation view, so a deleted entity reads null.
/datum/entity_narrate_entry
	var/atom/target

/// Starts tracking `A` under `unique_name`.
/datum/entity_narrate/proc/track(unique_name, atom/A)
	var/datum/entity_narrate_entry/entry = new
	rel_set(entry, nameof(entry.target), A)
	rel_add(src, nameof(entity_refs), entry, unique_name)

/// The entity tracked under `unique_name`, or null (never tracked, or deleted since).
/datum/entity_narrate/proc/tracked(unique_name)
	var/datum/entity_narrate_entry/entry = LAZYACCESS(entity_refs, unique_name)
	return entry?.target

/// Stops tracking `unique_name`.
/datum/entity_narrate/proc/untrack(unique_name)
	rel_add(src, nameof(entity_refs), null, unique_name)

/datum/prompt/choice/admin_narrate_remove
	rights = R_FUN
	timeout = 0
	title = "remove reference"
	question = "Choose which entity to remove"
	recheck_on_open = TRUE

/datum/prompt/choice/admin_narrate_clear
	rights = R_FUN
	timeout = 0
	title = "confirm"
	question = "Do you really want to clear your entity list?"
	choices = list("Yes", "No")
	buttons = TRUE
	recheck_on_open = TRUE


/datum/prompt/choice/admin_narrate_interface_replay
	timeout = 0
	rights = R_FUN
	recheck_on_open = TRUE

/datum/prompt/choice/admin_narrate_interface_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/choice/admin_narrate_interface_replay/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_narrate_interface_replay/refusal(given)
	return null

/datum/prompt/text/admin_narrate_interface_replay
	timeout = 0
	rights = R_FUN
	recheck_on_open = TRUE

/datum/prompt/text/admin_narrate_interface_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/text/admin_narrate_interface_replay/normalize(given)
	return istext(given) ? given : null

/datum/admin_verb/narrate_mob/proc/narrate_mob_replay_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)

/datum/prompt/text/admin_narrate_args_replay
	timeout = 0
	rights = R_FUN
	recheck_on_open = TRUE

/datum/prompt/text/admin_narrate_args_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/text/admin_narrate_args_replay/normalize(given)
	return istext(given) ? given : null

/datum/admin_verb/narrate_mob_args/proc/narrate_mob_args_replay_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer.captured["original_name"], A.answer.captured["original_mode"], A.answer.captured["original_message"], A.answer)
