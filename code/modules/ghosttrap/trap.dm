// This system is used to grab a ghost from observers with the required preferences and
// lack of bans set. See posibrain.dm for an example of how they are called/used. ~Z

GLOBAL_LIST(ghost_traps)

/proc/get_ghost_trap(trap_key)
	READS_FROM() // the table of traps is fixed at boot: no entity state
	if(!GLOB.ghost_traps)
		populate_ghost_traps()
	return GLOB.ghost_traps[trap_key]

/proc/populate_ghost_traps()
	READS_FROM() // builds the fixed table of traps once: no entity state
	GLOB.ghost_traps = list()
	for(var/traptype in typesof(/datum/ghosttrap))
		var/datum/ghosttrap/G = new traptype
		GLOB.ghost_traps[G.object] = G

/datum/ghosttrap
	var/object = "positronic brain"
	var/pref_check = BE_AI
	var/ghost_trap_message = "They are occupying a positronic brain now."
	var/ghost_trap_role = "Positronic Brain"

TYPE_TABLE_DECLARE(/datum/ghosttrap, ghosttrap_ban_checks, list(JOB_AI,JOB_CYBORG))

/// Why the candidate may not enter play as this trap's object, or null: the text of the refusal (an empty string for a ghost that cannot be asked at all).
/datum/ghosttrap/proc/candidate_refusal(mob/observer/dead/candidate)
	READS_FROM() // the bans and the respawn rules are read when the ghost asks, never cached
	if(!istype(candidate) || !candidate.client || !candidate.ckey)
		return /datum/msg/req_silent
	if(!candidate.MayRespawn())
		return span_infoplain("You have made use of the AntagHUD and hence cannot enter play as  [object].")
	if(islist(TYPE_TABLE_GET(src, ghosttrap_ban_checks)))
		for(var/bantype in TYPE_TABLE_GET(src, ghosttrap_ban_checks))
			if(jobban_isbanned(candidate, "[bantype]"))
				return span_infoplain("You are banned from one or more required roles and hence cannot enter play as  [object].")
	return null

// Check for bans, proper atom types, etc.
/datum/ghosttrap/proc/assess_candidate(mob/observer/dead/candidate)
	var/why = candidate_refusal(candidate)
	if(isnull(why))
		return 1
	if(istext(why))
		to_chat(candidate, why)
	return 0

// Print a message to all ghosts with the right prefs/lack of bans.
/datum/ghosttrap/proc/request_player(mob/target, request_string)
	if(!target)
		return
	for(var/mob/observer/dead/O in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(!O.MayRespawn())
			continue
		if(islist(TYPE_TABLE_GET(src, ghosttrap_ban_checks)))
			for(var/bantype in TYPE_TABLE_GET(src, ghosttrap_ban_checks))
				if(jobban_isbanned(O, "[bantype]"))
					continue
		if(pref_check && !(O.client.prefs.read_preference(/datum/preference/numeric/human/be_special) & pref_check)) // migrated
			continue
		if(O.client)
			to_chat(O, "[request_string]<a href='byond://?src=\ref[src];candidate=\ref[O];target=\ref[target]'>Click here</a> if you wish to play as this option.")

// Handles a response to request_player().
TOPIC_ACTION(/datum/ghosttrap, "candidate", PROC_REF(topic_candidate), TOPIC_REF("candidate", /mob/observer/dead, TOPIC_IN_MOBS), TOPIC_REF("target", /mob, TOPIC_IN_MOBS))

/datum/ghosttrap/proc/topic_candidate(mob/user, list/args)
	var/mob/observer/dead/candidate = args["candidate"]
	var/mob/target = args["target"]
	if(!target || !candidate)
		return
	if(candidate == user && assess_candidate(candidate) && !target.ckey)
		transfer_personality(candidate,target)
	return TRUE

// Shunts the ckey/mind into the target mob.
/datum/ghosttrap/proc/transfer_personality(mob/candidate, mob/target)
	if(!assess_candidate(candidate))
		return 0
	target.ckey = candidate.ckey
	if(target.mind)
		target.mind.assigned_role = "[ghost_trap_role]"
	announce_ghost_joinleave(candidate, 0, "[ghost_trap_message]")
	welcome_candidate(target)
	set_new_name(target)
	return 1

// Fluff!
/datum/ghosttrap/proc/welcome_candidate(mob/target)
	to_chat(target, span_infoplain(span_bold("You are a positronic brain, brought into existence on [station_name()].")))
	to_chat(target, span_infoplain(span_bold("As a synthetic intelligence, you answer to all crewmembers, as well as the AI.")))
	to_chat(target, span_infoplain(span_bold("Remember, the purpose of your existence is to serve the crew and the station. Above all else, do no harm.")))
	to_chat(target, span_infoplain(span_bold("Use say #b to speak to other artificial intelligences.")))
	var/turf/T = get_turf(target)
	T.visible_message(span_infoplain(span_bold("\The [src]") + " chimes quietly."))
	var/obj/item/mmi/digital/posibrain/P = target.loc
	if(!istype(P)) //wat
		return
	P.searching = 0
	P.name = "positronic brain ([P.get_occupant()?.name])"
	P.icon_state = "posibrain-occupied"

// Allows people to set their own name. May or may not need to be removed for posibrains if people are dumbasses.
/datum/ghosttrap/proc/set_new_name(mob/target)
	open_request(src, /datum/prompt/text/ghosttrap_name, PROC_REF(ghosttrap_name_answered), answerer = target)

/datum/ghosttrap/proc/ghosttrap_name_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/mob/target = context.answer.answerer
	var/newname = sanitizeSafe(context.answer.value, MAX_NAME_LEN)
	if (newname != "")
		target.real_name = newname
		target.name = target.real_name
	SStgui.update_uis(src)

// Doona pods and walking mushrooms.
/datum/ghosttrap/plant
	object = "living plant"
	pref_check = BE_PLANT
	ghost_trap_message = "They are occupying a living plant now."
	ghost_trap_role = "Plant"

TYPE_TABLE(/datum/ghosttrap/plant, ghosttrap_ban_checks, list(JOB_DIONAEA))

/datum/ghosttrap/plant/welcome_candidate(mob/target)
	to_chat(target, span_infoplain(span_alium(span_bold("You awaken slowly, stirring into sluggish motion as the air caresses you."))))
	// This is a hack, replace with some kind of species blurb proc.
	if(istype(target,/mob/living/carbon/alien/diona))
		to_chat(target, span_infoplain(span_bold("You are \a [target], one of a race of drifting interstellar plantlike creatures that sometimes share their seeds with human traders.")))
		to_chat(target, span_infoplain(span_bold("Too much darkness will send you into shock and starve you, but light will help you heal.")))

/datum/prompt/text/ghosttrap_name
	title = "Name change"
	question = "Enter a name, or leave blank for the default name."
	max_len = MAX_NAME_LEN
	encode = FALSE
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/text/ghosttrap_name/normalize(given)
	return istext(given) ? strip_name_tokens(given) : null

/datum/prompt/text/ghosttrap_name/recheck_extra()
	var/datum/ghosttrap/trap = owner
	var/mob/target = answerer
	if(!istype(trap) || QDELETED(trap) || !istype(target) || QDELETED(target))
		return "gone"
	return null
