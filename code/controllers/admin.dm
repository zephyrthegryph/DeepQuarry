// Clickable stat() button.
/obj/effect/statclick
	name = "Initializing..."
	blocks_emissive = EMISSIVE_BLOCK_NONE
	var/target

INITIALIZE_IMMEDIATE(/obj/effect/statclick)

// ALLOW(init/CTOR_ARGS): text and target are constructor arguments from whoever builds it
/obj/effect/statclick/Initialize(mapload, text, target)
	. = ..()
	name = text
	src.target = target

/obj/effect/statclick/proc/cleanup()
	// ALLOW(lifecycle): the stat panel link is dropped when its panel entry is cleared
	qdel(src)

/obj/effect/statclick/proc/update(text)
	name = text
	return src

/obj/effect/statclick/debug
	var/class

/obj/effect/statclick/debug/Click()
	var/mob/user = usr // ALLOW(sys_usr_outside_verb): BYOND Click supplies the initiating diagnostic viewer.
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

	var/pick = verb_ask(user, "pick", args, /datum/om/prompt/choice, message = "Choose a controller to debug/view variables of.", title = "VV controller:", choices = options)
	if(!pick)
		return
	var/datum/D = options[pick]
	if(!istype(D))
		return
	feedback_add_details("admin_verb", "DebugController")
	message_admins("Admin [key_name_admin(user)] is debugging the [pick] controller.")
	user.debug_variables(D)
