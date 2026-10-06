// Clickable stat() button.
/obj/effect/statclick
	name = "Initializing..."
	blocks_emissive = EMISSIVE_BLOCK_NONE
	var/target

INITIALIZE_IMMEDIATE(/obj/effect/statclick)

CAPABILITIES(/obj/effect/statclick)
	param(nameof(name), pos = 1)
	param(nameof(target), pos = 2)

/obj/effect/statclick/proc/cleanup()
	spent(src)

/obj/effect/statclick/proc/update(text)
	name = text
	return src

/obj/effect/statclick/debug
	var/class

CAPABILITIES(/obj/effect/statclick/debug)
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm). An admin opens the target's variables.
/obj/effect/statclick/debug/proc/click_input(datum/act/input/A)
	. = TRUE
	var/mob/user = A.actor
	if(!check_rights_for(user.client, R_HOLDER) || !target)
		return
	if(!class)
		if(istype(target, /datum/system))
			class = "system"
		else if(istype(target, /datum/controller))
			class = "controller"
		else if(isdatum(target))
			class = "datum"
		else
			class = "unknown"

	user.client.debug_variables(target)
	message_admins("Admin [key_name_admin(user)] is debugging the [target] [class].")

ADMIN_VERB(restart_controller, R_DEBUG, "Restart Controller", "Restart one of the various periodic loop controllers for the game (be careful!)", ADMIN_CATEGORY_DEBUG_GAME, controller in list("Kernel", "Watchdog"))
	switch(controller)
		if("Kernel")
			Recreate_kernel()
			feedback_add_details("admin_verb","RKernel")
		if("Watchdog")
			Kernel.start_watchdog()
			feedback_add_details("admin_verb","RWatchdog")

	message_admins("Admin [key_name_admin(user)] has restarted the [controller] controller.")

ADMIN_VERB(debug_antagonist_template, R_DEBUG, "Debug Antagonist", "Debug an antagonist template", ADMIN_CATEGORY_DEBUG_GAME, antag_type in SSantag.all_antag_types)
	var/datum/antagonist/antag = SSantag.all_antag_types[antag_type]
	if(antag)
		user.debug_variables(antag)
		message_admins("Admin [key_name_admin(user)] is debugging the [antag.role_text] template.")

ADMIN_VERB(debug_controller, R_DEBUG, "Debug Controller", "Debug the various periodic loop controllers for the game (be careful!)", ADMIN_CATEGORY_DEBUG_GAME)
	var/list/options = list()
	options["Kernel"] = Kernel
	options["Watchdog"] = Kernel.watchdog
	options["Configuration"] = config

	// The systems keep their SS<X> names.
	for(var/datum/system/S as anything in kernel_pure_systems())
		var/strtype = "SS[get_end_section_of_type(S.type)]"
		if(!options[strtype])
			options[strtype] = S

	//Goon PS stuff, and other yet-to-be-subsystem things.
	options["LEGACY: cameranet"] = GLOB.cameranet

	var/pick
	var/datum/request/resumed = length(args) > 1 ? args[2] : null
	if(istype(resumed, /datum/prompt/choice/admin_debug_controller) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(debug_controller_answered))
		pick = resumed.value
	else
		open_request(src, /datum/prompt/choice/admin_debug_controller, PROC_REF(debug_controller_answered), answerer = user.mob, question = "Choose a controller to debug/view variables of.", title = "VV controller:", choices = options)
		return
	if(!pick)
		return
	var/datum/D = options[pick]
	if(!istype(D))
		return
	feedback_add_details("admin_verb", "DebugController")
	message_admins("Admin [key_name_admin(user)] is debugging the [pick] controller.")
	user.debug_variables(D)


/datum/prompt/choice/admin_debug_controller
	timeout = 0
	rights = R_DEBUG
	recheck_on_open = TRUE

/datum/prompt/choice/admin_debug_controller/normalize(given)
	return given

/datum/prompt/choice/admin_debug_controller/refusal(given)
	return null

/datum/prompt/choice/admin_debug_controller/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/admin_verb/debug_controller/proc/debug_controller_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)
