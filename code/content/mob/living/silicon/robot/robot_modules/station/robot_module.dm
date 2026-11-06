/obj/item/robot_module
	name = "robot module"
	icon = 'icons/obj/module.dmi'
	icon_state = "std_module"
	w_class = ITEMSIZE_NO_CONTAINER
	item_state = "std_mod"
	var/pto_type = null
	var/hide_on_manifest = FALSE
	var/list/channels
	var/list/networks
	var/languages = list(LANGUAGE_SOL_COMMON= 1,
					LANGUAGE_TRADEBAND	= 1,
					LANGUAGE_UNATHI		= 0,
					LANGUAGE_SIIK		= 0,
					LANGUAGE_SKRELLIAN	= 0,
					LANGUAGE_GUTTER		= 0,
					LANGUAGE_SCHECHI	= 0,
					LANGUAGE_SIGN		= 0,
					LANGUAGE_BIRDSONG	= 0,
					LANGUAGE_SAGARU		= 0,
					LANGUAGE_CANILUNZT	= 0,
					LANGUAGE_ECUREUILIAN= 0,
					LANGUAGE_DAEMON		= 0,
					LANGUAGE_ENOCHIAN	= 0,
					LANGUAGE_DRUDAKAR	= 0)
	var/can_be_pushed = 0
	var/no_slip = 0
	var/list/modules = list() // ALLOW(instance_list): d: every robot module holds its items
	var/list/datum/matter_synth/synths = list() // ALLOW(instance_list): d: filled per module type when the module is created
	var/list/emag = list() // ALLOW(instance_list): d: robot module item lists, filled per module type
	var/list/subsystems = list() // ALLOW(instance_list): d: filled per module type when the module is created
	/// Upgrade type paths this module accepts (types, not instances).
	var/list/supported_upgrades

	// Bookkeeping
	var/list/original_languages
	var/list/added_networks
	var/ui_theme
	var/idcard_type = /obj/item/card/id/synthetic

	// Module capabilities other systems read, instead of checking module types.
	/// Staffing key this module counts toward for event weighting (DEPARTMENT_* or job title). Null for none.
	var/staffing_role
	/// Can name door and windoor assemblies.
	var/names_assemblies = FALSE
	/// Accepts trash fed to it.
	var/eats_trash = FALSE
	/// Can use the security emotes.
	var/security_emotes = FALSE

CAPABILITIES(/obj/item/robot_module)
	setup(PROC_REF(configure_robot_module))
	owns_many(nameof(emag))
	owns_many(nameof(modules))
	owns_many(nameof(synths), /datum/matter_synth)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(emp_synths)))

/obj/item/robot_module/proc/hide_on_manifest()
	. = hide_on_manifest

/obj/item/robot_module/proc/configure_robot_module()

	if(!isrobot(loc))
		return

	var/mob/living/silicon/robot/R = loc
	rel_set(R, nameof(R.module), src)

	add_camera_networks(R)
	add_languages(R)
	add_subsystems(R)
	apply_status_flags(R)
	handle_shell(R)

	if(R.radio)
		if(R.shell)
			channels = R.mainframe.aiRadio.channels
		R.radio.recalculateChannels()

	R.set_default_module_icon()
	if(!R.client)
		R.icon_selected = FALSE			// It wasnt a player selecting icon? Let them do it later!

	create_equipment(R)

	for(var/obj/item/I in modules)
		I.set_canremove(FALSE)

	on_robot_equip(R)

/obj/item/robot_module/proc/create_equipment(mob/living/silicon/robot/robot)
	if(!istype(robot.idcard, idcard_type))
		own_clear(robot, nameof(robot.idcard), OWN_DELETE)
	robot.init_id(idcard_type)
	return

/// The module has been installed in `robot`. Modules compose what they add
/// to the chassis here (the sleeper belly: riding, belly light, death eject).
/obj/item/robot_module/proc/on_robot_equip(mob/living/silicon/robot/robot)
	robot.add_robot_belly()

/// The module is leaving `robot`. Undo on_robot_equip().
/obj/item/robot_module/proc/on_robot_unequip(mob/living/silicon/robot/robot)
	own_clear(robot, nameof(robot.robot_belly), OWN_DELETE)

// Reset the module and delete it
/obj/item/robot_module/proc/reset_module(mob/living/silicon/robot/robot)
	on_robot_unequip(robot)
	remove_camera_networks(robot)
	remove_languages(robot)
	remove_subsystems(robot)
	remove_status_flags(robot)

	if(robot.radio)
		robot.radio.recalculateChannels()
	robot.set_default_module_icon()

	robot.set_scrubbing(FALSE)

	modules -= robot.idcard // ALLOW(ownership): the robot owns its idcard (robot.idcard); the module only lists it as a usable item
	if(robot.idcard.loc != robot)
		robot.idcard.forceMove(robot)
	rel_take(robot, nameof(robot.module))
	consume(src, robot)

/// Module items are pulsed once by content recursion: stowed ones inside the
/// module, equipped ones inside the robot. Only the matter synths (datums)
/// need pulsing here.
/obj/item/robot_module/proc/emp_synths(datum/act/A)
	var/datum/notice/hit/emp/N = A
	for(var/datum/matter_synth/S in synths)
		S.emp_act(N.packet.severity)

/obj/item/robot_module/proc/respawn_consumable(mob/living/silicon/robot/R, rate)
	SHOULD_CALL_PARENT(TRUE)
	if(!LAZYLEN(synths))
		return

	for(var/datum/matter_synth/T in synths)
		T.add_charge(T.recharge_rate * rate)

/obj/item/robot_module/proc/rebuild()//Rebuilds the list so it's possible to add/remove items from the module
	// In place: the members keep their owners (the robot's idcard is listed, not owned, here).
	if(modules)
		listclearnulls(modules)

/obj/item/robot_module/proc/add_languages(mob/living/silicon/robot/R)
	// Stores the languages as they were before receiving the module, and whether they could be synthezized.
	for(var/datum/language/language_datum in R.languages)
		LAZYSET(original_languages, language_datum, (language_datum in R.speech_synthesizer_langs))

	for(var/language in languages)
		R.add_language(language, languages[language])

/obj/item/robot_module/proc/remove_languages(mob/living/silicon/robot/R)
	// Clear all added languages, whether or not we originally had them.
	for(var/language in languages)
		R.remove_language(language)

	// Then add back all the original languages, and the relevant synthezising ability
	for(var/original_language in original_languages)
		R.add_language(original_language, LAZYACCESS(original_languages, original_language))
	LAZYCLEARLIST(original_languages)

/obj/item/robot_module/proc/add_camera_networks(mob/living/silicon/robot/R)
	if(R.camera && (NETWORK_ROBOTS in R.camera.network))
		for(var/network in networks)
			if(!(network in R.camera.network))
				R.camera.add_network(network)
				LAZYOR(added_networks, network)

/obj/item/robot_module/proc/remove_camera_networks(mob/living/silicon/robot/R)
	if(R.camera)
		if(length(added_networks)) R.camera.remove_networks(added_networks)
	LAZYCLEARLIST(added_networks)

/obj/item/robot_module/proc/add_subsystems(mob/living/silicon/robot/R)
	for(var/granted_path in subsystems)
		grant(R, granted_verb(granted_path), src)

/obj/item/robot_module/proc/remove_subsystems(mob/living/silicon/robot/R)
	for(var/granted_path in subsystems)
		revoke(R, granted_verb(granted_path), src)

/obj/item/robot_module/proc/apply_status_flags(mob/living/silicon/robot/R)
	if(!can_be_pushed)
		R.add_push_disable_source(SRC_PUSH_ROBOT_MODULE)

/obj/item/robot_module/proc/remove_status_flags(mob/living/silicon/robot/R)
	if(!can_be_pushed)
		R.remove_push_disable_source(SRC_PUSH_ROBOT_MODULE)

/obj/item/robot_module/proc/handle_shell(mob/living/silicon/robot/R)
	if(R.braintype == BORG_BRAINTYPE_AI_SHELL)
		channels = list(
			CHANNEL_MEDICAL = 1,
			CHANNEL_ENGINEERING = 1,
			CHANNEL_SECURITY = 1,
			CHANNEL_SERVICE = 1,
			CHANNEL_SUPPLY = 1,
			CHANNEL_SCIENCE = 1,
			CHANNEL_COMMAND = 1,
			CHANNEL_EXPLORATION = 1
			)

/obj/item/robot_module/proc/add_item_with_reagents(obj/item/stack/item_with_synth)
	var/list/item_synths = list()
	for(var/datum/matter_synth/matter_synth as anything in item_with_synth.synths)
		var/found = FALSE
		for(var/datum/matter_synth/synth as anything in synths)
			if(matter_synth.type == synth.type)
				item_synths += synth
				found = TRUE
				break
		if(!found)
			var/datum/matter_synth/new_synth = new matter_synth.type(10000)
			item_synths += new_synth
			rel_add(src, nameof(synths), new_synth)
	rel_clear(item_with_synth, nameof(item_with_synth.synths))
	for(var/datum/matter_synth/linked_synth as anything in item_synths)
		item_with_synth.add_synth(linked_synth)

/obj/item/robot_module/proc/add_item(atom/movable/new_item, mob/living/silicon/robot/robot)
	if(istype(new_item, /obj/item/card/id))
		if(robot.idcard)
			modules -= robot.idcard // ALLOW(ownership): the robot owns its idcard (robot.idcard); the module only lists it as a usable item
			own_clear(robot, nameof(robot.idcard), OWN_DELETE)
		own_move(new_item, robot, nameof(robot.idcard))
		modules |= new_item // ALLOW(ownership): the robot owns its idcard (robot.idcard); the module only lists it as a usable item
		new_item.forceMove(src)
		robot.hud_used?.update_robot_modules_display()
		return
	move_into(src, nameof(src.modules), new_item)
	robot.hud_used?.update_robot_modules_display()

	if(istype(new_item, /obj/item/robotic_multibelt/materials))
		var/obj/item/robotic_multibelt/materials/mat_belt = new_item
		for(var/obj/item/stack as anything in mat_belt.cyborg_integrated_tools)
			add_item_with_reagents(stack)

	if(istype(new_item, /obj/item/stack))
		add_item_with_reagents(new_item)

	if(istype(new_item, /obj/item/matter_decompiler) || istype(new_item, /obj/item/dogborg/sleeper/compactor/decompiler))
		var/obj/item/matter_decompiler/item_with_matter = new_item
		if(item_with_matter.metal)
			var/found = FALSE
			for(var/datum/matter_synth/synth as anything in synths)
				if(item_with_matter.metal.type == synth.type)
					rel_set(item_with_matter, nameof(item_with_matter.metal), synth)
					found = TRUE
					break
			if(!found)
				var/datum/matter_synth/metal = new /datum/matter_synth/metal(40000)
				rel_set(item_with_matter, nameof(item_with_matter.metal), metal)
				rel_add(src, nameof(synths), metal)
		if(item_with_matter.glass)
			var/found = FALSE
			for(var/datum/matter_synth/synth as anything in synths)
				if(item_with_matter.glass.type == synth.type)
					rel_set(item_with_matter, nameof(item_with_matter.glass), synth)
					found = TRUE
					break
			if(!found)
				var/datum/matter_synth/glass = new /datum/matter_synth/glass(40000)
				rel_set(item_with_matter, nameof(item_with_matter.glass), glass)
				rel_add(src, nameof(synths), glass)
		if(item_with_matter.wood)
			var/found = FALSE
			for(var/datum/matter_synth/synth as anything in synths)
				if(item_with_matter.wood.type == synth.type)
					rel_set(item_with_matter, nameof(item_with_matter.wood), synth)
					found = TRUE
					break
			if(!found)
				var/datum/matter_synth/wood = new /datum/matter_synth/wood(40000)
				rel_set(item_with_matter, nameof(item_with_matter.wood), wood)
				rel_add(src, nameof(synths), wood)
		if(item_with_matter.plastic)
			var/found = FALSE
			for(var/datum/matter_synth/synth as anything in synths)
				if(item_with_matter.plastic.type == synth.type)
					rel_set(item_with_matter, nameof(item_with_matter.plastic), synth)
					found = TRUE
					break
			if(!found)
				var/datum/matter_synth/plastic = new /datum/matter_synth/plastic(40000)
				rel_set(item_with_matter, nameof(item_with_matter.plastic), plastic)
				rel_add(src, nameof(synths), plastic)
