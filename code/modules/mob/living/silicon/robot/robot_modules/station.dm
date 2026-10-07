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
	owns_many(nameof(emag))
	owns_many(nameof(modules))
	owns_many(nameof(synths), /datum/matter_synth)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(emp_synths)))

/obj/item/robot_module/proc/hide_on_manifest()
	. = hide_on_manifest

// ALLOW(init/INSTANCE_STATE): binds to the robot it is made inside and fits that robot out
/obj/item/robot_module/Initialize(mapload)
	. = ..()

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
		I.canremove = FALSE

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

	robot.scrubbing = FALSE

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
		rel_add(item_with_synth, nameof(item_with_synth.synths), linked_synth)

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

// Cyborgs (non-drones), default loadout. This will be given to every module.
/obj/item/robot_module/robot/create_equipment(mob/living/silicon/robot/robot)
	..()
	var/datum/matter_synth/water = new /datum/matter_synth(500)
	water.name = "Water reserves"
	water.recharge_rate = 10
	water.max_energy = 1000
	rel_set(robot, nameof(robot.water_res), water)
	rel_add(src, nameof(synths), water)
	var/obj/item/robot_tongue/T = new /obj/item/robot_tongue(src)
	rel_set(T, nameof(T.water), water)
	rel_add(src, nameof(modules), T)
	var/obj/item/gps/robot/robot_gps = new /obj/item/gps/robot(src)
	adjust_gps(robot_gps)
	rel_add(src, nameof(modules), robot_gps)
	rel_add(src, nameof(modules), new /obj/item/boop_module(src))
	rel_add(src, nameof(modules), new /obj/item/flash/robot(src))
	rel_add(src, nameof(modules), new /obj/item/extinguisher(src))
	rel_add(src, nameof(modules), new /obj/item/tool/crowbar/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/melee/robotic/jaws/small(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/scene(src))
	rel_add(src, nameof(modules), new /obj/item/robo_dice(src))

/obj/item/robot_module/robot/proc/adjust_gps(obj/item/gps/robot/robot_gps)
	return

/obj/item/robot_module/robot/standard
	name = "standard robot module"
	pto_type = PTO_CIVILIAN

/obj/item/robot_module/robot/standard/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/tool/wrench/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/healthanalyzer(src))
	rel_add(src, nameof(modules), new /obj/item/melee/baton/loaded(src))
	rel_add(src, nameof(emag), new /obj/item/melee/energy/sword(src))

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/compactor/generic(src))
	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src))

/obj/item/robot_module/robot/medical
	staffing_role = DEPARTMENT_MEDICAL
	name = "medical robot module"
	channels = list(CHANNEL_MEDICAL = 1)
	networks = list(NETWORK_MEDICAL)
	subsystems = list(/mob/living/silicon/proc/subsystem_crew_monitor)
	pto_type = PTO_MEDICAL
	supported_upgrades = list(/obj/item/borg/upgrade/restricted/bellycapupgrade)

//This is a constant back and forth debate. 11 years ago, the 'medical' borg was split into surgery and crisis.
//Two years ago(?), they were combined into Crisis elsewhere and the idea seems to be well appreciated.
//However, given this seems as though it will remain a hot topic for as long as SS13 exists, we are going to leave the surgeon module here in the event that we split them. Again.
//This also goes for the sprite datums. It's be a lot of work to 'clear' them of having surgery in their path just to have to split them again in 2-3 years.
/obj/item/robot_module/robot/medical/surgeon
	name = "surgeon robot module"

/obj/item/robot_module/robot/medical/surgeon/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/healthanalyzer(src))
	rel_add(src, nameof(modules), new /obj/item/sleevemate(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/borghypo/surgeon(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/medical(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/medical(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/medical(src))
	rel_add(src, nameof(modules), new /obj/item/shockpaddles/robot(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/dropper(src)) // Allows surgeon borg to fix necrosis
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/syringe(src))

	var/obj/item/reagent_containers/spray/PS = new /obj/item/reagent_containers/spray(src)

	rel_add(src, nameof(emag), PS)
	PS.reagents.add_reagent(REAGENT_ID_PACID, 250)
	PS.name = "Polyacid spray"

	var/datum/matter_synth/medicine = new /datum/matter_synth/medicine(10000)
	rel_add(src, nameof(synths), medicine)

	var/obj/item/stack/nanopaste/N = new /obj/item/stack/nanopaste(src)
	var/obj/item/stack/medical/advanced/bruise_pack/B = new /obj/item/stack/medical/advanced/bruise_pack(src)
	var/obj/item/stack/medical/advanced/ointment/O = new /obj/item/stack/medical/advanced/ointment(src) // edit: we have burn surgeries so they should be able to do them
	N.uses_charge = 1
	N.charge_costs = list(1000)
	rel_add(N, nameof(N.synths), medicine)
	B.uses_charge = 1
	B.charge_costs = list(1000)
	rel_add(B, nameof(B.synths), medicine)
	O.uses_charge = 1
	O.charge_costs = list(1000)
	rel_add(O, nameof(O.synths), medicine)
	rel_add(src, nameof(modules), N)
	rel_add(src, nameof(modules), B)
	rel_add(src, nameof(modules), O)

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/trauma(src))
	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src))

/obj/item/robot_module/robot/medical/surgeon/respawn_consumable(mob/living/silicon/robot/R, amount)

	var/obj/item/reagent_containers/syringe/S = locate_in_list(src.modules, /obj/item/reagent_containers/syringe)
	if(S && S.mode == 2)
		S.reagents.clear_reagents()
		S.mode = initial(S.mode)
		S.desc = initial(S.desc)
		S.update_icon()

	var/obj/item/reagent_containers/spray/PS = locate_in_list(src.emag, /obj/item/reagent_containers/spray)
	if(PS)
		PS.reagents.add_reagent(REAGENT_ID_PACID, 2 * amount)

	..()

/obj/item/robot_module/robot/medical/crisis
	name = "crisis robot module"

/obj/item/robot_module/robot/medical/crisis/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/healthanalyzer(src))
	rel_add(src, nameof(modules), new /obj/item/sleevemate(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_scanner/adv(src))
	rel_add(src, nameof(modules), new /obj/item/roller_holder(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/borghypo/crisis(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/glass/beaker/large/borg(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/dropper/industrial(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/syringe(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/medical(src))
	rel_add(src, nameof(modules), new /obj/item/shockpaddles/robot(src))
	//Surgeon Modules below
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/medical(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/medical(src))
	//Surgeon Modules End
	rel_add(src, nameof(modules), new /obj/item/inflatable_dispenser/robot(src))
	rel_add(src, nameof(modules), new /obj/item/holosign_creator/medical(src))
	var/obj/item/reagent_containers/spray/PS = new /obj/item/reagent_containers/spray(src)
	rel_add(src, nameof(emag), PS)
	PS.reagents.add_reagent(REAGENT_ID_PACID, 250)
	PS.name = "Polyacid spray"

	var/datum/matter_synth/medicine = new /datum/matter_synth/medicine(30000)
	rel_add(src, nameof(synths), medicine)

	var/obj/item/stack/medical/advanced/clotting/C = new (src)
	var/obj/item/stack/medical/advanced/ointment/O = new /obj/item/stack/medical/advanced/ointment(src)
	var/obj/item/stack/medical/advanced/bruise_pack/B = new /obj/item/stack/medical/advanced/bruise_pack(src)
	var/obj/item/stack/medical/splint/S = new /obj/item/stack/medical/splint(src)
	C.uses_charge = 1
	C.charge_costs = list(5000)
	rel_add(C, nameof(C.synths), medicine)
	O.uses_charge = 1
	O.charge_costs = list(1000)
	rel_add(O, nameof(O.synths), medicine)
	B.uses_charge = 1
	B.charge_costs = list(1000)
	rel_add(B, nameof(B.synths), medicine)
	S.uses_charge = 1
	S.charge_costs = list(1000)
	rel_add(S, nameof(S.synths), medicine)
	rel_add(src, nameof(modules), O)
	rel_add(src, nameof(modules), B)
	rel_add(src, nameof(modules), S)
	rel_add(src, nameof(modules), C)

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper(src))
	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src)) //Pounce

/obj/item/robot_module/robot/medical/crisis/respawn_consumable(mob/living/silicon/robot/R, amount)

	var/obj/item/reagent_containers/syringe/S = locate_in_list(src.modules, /obj/item/reagent_containers/syringe)
	if(S && S.mode == 2)
		S.reagents.clear_reagents()
		S.mode = initial(S.mode)
		S.desc = initial(S.desc)
		S.update_icon()

	var/obj/item/reagent_containers/spray/PS = locate_in_list(src.emag, /obj/item/reagent_containers/spray)
	if(PS)
		PS.reagents.add_reagent(REAGENT_ID_PACID, 2 * amount)

	..()

/obj/item/robot_module/robot/engineering
	staffing_role = DEPARTMENT_ENGINEERING
	names_assemblies = TRUE
	name = "engineering robot module"
	channels = list(CHANNEL_ENGINEERING = 1)
	networks = list(NETWORK_ENGINEERING)
	subsystems = list(/mob/living/silicon/proc/subsystem_power_monitor)
	pto_type = PTO_ENGINEERING

/obj/item/robot_module/robot/engineering/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt(src))
	rel_add(src, nameof(modules), new /obj/item/borg/sight/meson(src))
	rel_add(src, nameof(modules), new /obj/item/t_scanner(src))
	rel_add(src, nameof(modules), new /obj/item/analyzer(src))
	rel_add(src, nameof(modules), new /obj/item/assembly/signaler(src)) // Anomaly handling
	rel_add(src, nameof(modules), new /obj/item/geiger(src))
	rel_add(src, nameof(modules), new /obj/item/taperoll/engineering(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/engineering(src))
	rel_add(src, nameof(modules), new /obj/item/lightreplacer(src))
	rel_add(src, nameof(modules), new /obj/item/pipe_dispenser(src))
	rel_add(src, nameof(modules), new /obj/item/floor_painter(src))
	rel_add(src, nameof(modules), new /obj/item/rms(src))
	rel_add(src, nameof(modules), new /obj/item/inflatable_dispenser/robot(src))
	rel_add(src, nameof(emag), new /obj/item/melee/robotic/baton/arm(src))
	rel_add(src, nameof(modules), new /obj/item/rcd/electric/mounted/borg(src))
	rel_add(src, nameof(modules), new /obj/item/pickaxe/plasmacutter/borg(src))
	rel_add(src, nameof(modules), new /obj/item/dogborg/stasis_clamp(src))
	rel_add(src, nameof(modules), new /obj/item/storage/pouch/eng_parts/borg(src))
	rel_add(src, nameof(modules), new /obj/item/holosign_creator/combifan(src))

	var/datum/matter_synth/metal = new /datum/matter_synth/metal(40000)
	var/datum/matter_synth/glass = new /datum/matter_synth/glass(40000)
	var/datum/matter_synth/plasteel = new /datum/matter_synth/plasteel(20000)
	var/datum/matter_synth/wood = new /datum/matter_synth/wood(40000)
	var/datum/matter_synth/plastic = new /datum/matter_synth/plastic(40000)

	var/datum/matter_synth/wire = new /datum/matter_synth/wire()
	rel_add(src, nameof(synths), metal)
	rel_add(src, nameof(synths), glass)
	rel_add(src, nameof(synths), plasteel)
	rel_add(src, nameof(synths), wood)
	rel_add(src, nameof(synths), plastic)
	rel_add(src, nameof(synths), wire)

	var/obj/item/dogborg/sleeper/compactor/decompiler/BD = new /obj/item/dogborg/sleeper/compactor/decompiler(src)
	rel_set(BD, nameof(BD.metal), metal)
	rel_set(BD, nameof(BD.glass), glass)
	rel_set(BD, nameof(BD.wood), wood)
	rel_set(BD, nameof(BD.plastic), plastic)
	rel_add(src, nameof(modules), BD)

	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/materials(src))
	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src))

/obj/item/robot_module/robot/security
	staffing_role = DEPARTMENT_SECURITY
	security_emotes = TRUE
	name = "security robot module"
	channels = list(CHANNEL_SECURITY = 1)
	networks = list(NETWORK_SECURITY)
	subsystems = list(/mob/living/silicon/proc/subsystem_crew_monitor)
	supported_upgrades = list(/obj/item/borg/upgrade/restricted/tasercooler, /obj/item/borg/upgrade/restricted/bellycapupgrade)
	pto_type = PTO_SECURITY

/obj/item/robot_module/robot/security/general
	name = "security robot module"

/obj/item/robot_module/robot/security/general/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/handcuffs/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/melee/robotic/baton(src))
	rel_add(src, nameof(modules), new /obj/item/gun/energy/robotic/taser(src))
	rel_add(src, nameof(modules), new /obj/item/taperoll/police(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/spray/pepper(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/security(src))
	rel_add(src, nameof(modules), new /obj/item/gun/energy/robotic/phasegun(src)) // Phasegun for regular sec cyborg.
	rel_add(src, nameof(modules), new /obj/item/ticket_printer(src))
	rel_add(src, nameof(emag), new /obj/item/gun/energy/robotic/laser/rifle(src))

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/K9(src)) //Eat criminals. Bring them to the brig.
	rel_add(src, nameof(modules), new /obj/item/dogborg/pounce(src)) //Pounce

/obj/item/robot_module/robot/security/respawn_consumable(mob/living/silicon/robot/R, amount)
	..()
	var/obj/item/flash/F = locate_in_list(src.modules, /obj/item/flash)
	if(F && F.broken)
		F.broken = 0
		F.times_used = 0
		F.icon_state = "flash"
	else if(F.times_used)
		F.times_used--
	var/obj/item/gun/energy/robotic/taser/T = locate_in_list(src.modules, /obj/item/gun/energy/robotic/taser)
	if(!T)
		return
	if(T.power_supply.charge < T.power_supply.maxcharge)
		T.power_supply.give(T.charge_cost * amount)
		T.update_icon()
	else
		T.charge_tick = 0

/obj/item/robot_module/robot/janitor
	staffing_role = JOB_JANITOR
	eats_trash = TRUE
	name = "janitorial robot module"
	channels = list(CHANNEL_SERVICE = 1)
	pto_type = PTO_CIVILIAN

/obj/item/robot_module/robot/janitor/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/soap/nanotrasen(src))
	rel_add(src, nameof(modules), new /obj/item/storage/bag/trash(src))
	rel_add(src, nameof(modules), new /obj/item/mop(src))
	rel_add(src, nameof(modules), new /obj/item/pupscrubber(src))
	rel_add(src, nameof(modules), new /obj/item/lightreplacer(src))
	rel_add(src, nameof(modules), new /obj/item/vac_attachment(src))
	rel_add(src, nameof(modules), new /obj/item/borg/sight/janitor(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/glass/bucket/cyborg(src))
	var/obj/item/reagent_containers/spray/LS = new /obj/item/reagent_containers/spray(src)
	rel_add(src, nameof(emag), LS)
	LS.reagents.add_reagent(REAGENT_ID_LUBE, 250)
	LS.name = "Lube spray"

	//Starts empty. Can only recharge with recycled material.
	var/datum/matter_synth/metal = new /datum/matter_synth/metal()
	metal.name = "Steel reserves"
	metal.recharge_rate = 0
	metal.max_energy = 50000
	metal.energy = 0
	var/datum/matter_synth/glass = new /datum/matter_synth/glass()
	glass.name = "Glass reserves"
	glass.recharge_rate = 0
	glass.max_energy = 50000
	glass.energy = 0

	rel_add(src, nameof(synths), metal)
	rel_add(src, nameof(synths), glass)

	//Sheet refiners can only produce raw sheets.
	var/obj/item/stack/material/cyborg/steel/M = new (src)
	M.name = "steel recycler"
	M.desc = "A device that refines recycled steel into sheets."
	rel_add(M, nameof(M.synths), metal)
	// Shared recipe tables, like material.get_recipes(): never owned by one stack.
	var/static/list/steel_recycler_recipes = list(new /datum/stack_recipe("steel sheet", /obj/item/stack/material/steel, 1, 1, 20))
	var/static/list/glass_recycler_recipes = list(new /datum/stack_recipe("glass sheet", /obj/item/stack/material/glass, 1, 1, 20))
	M.recipes = steel_recycler_recipes
	rel_add(src, nameof(modules), M)

	var/obj/item/stack/material/cyborg/glass/G = new (src)
	G.name = "glass recycler"
	G.desc = "A device that refines recycled glass into sheets."
	G.material = get_material_by_name("placeholder") //Hacky shit but we want sheets, not windows.
	rel_add(G, nameof(G.synths), glass)
	G.recipes = glass_recycler_recipes
	rel_add(src, nameof(modules), G)

	var/obj/item/dogborg/sleeper/compactor/C = new /obj/item/dogborg/sleeper/compactor(src)
	rel_set(C, nameof(C.metal), metal)
	rel_set(C, nameof(C.glass), glass)
	rel_add(src, nameof(modules), C)

	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src)) //Pounce

/obj/item/robot_module/robot/janitor/respawn_consumable(mob/living/silicon/robot/R, amount)
	..()
	var/obj/item/lightreplacer/LR = locate_in_list(src.modules, /obj/item/lightreplacer)
	LR?.Charge(R, amount)

	var/obj/item/reagent_containers/spray/LS = locate_in_list(src.emag, /obj/item/reagent_containers/spray)
	if(LS)
		LS.reagents.add_reagent(REAGENT_ID_LUBE, 2 * amount)

/obj/item/robot_module/robot/clerical
	name = "service robot module"
	channels = list(
		CHANNEL_SERVICE = 1,
		CHANNEL_COMMAND = 1
		)
	languages = list(
					LANGUAGE_SOL_COMMON	= 1,
					LANGUAGE_TRADEBAND	= 1,
					LANGUAGE_UNATHI		= 1,
					LANGUAGE_SIIK		= 1,
					LANGUAGE_SKRELLIAN	= 1,
					LANGUAGE_ROOTLOCAL	= 0,
					LANGUAGE_GUTTER		= 1,
					LANGUAGE_SCHECHI	= 1,
					LANGUAGE_SIGN		= 0,
					LANGUAGE_BIRDSONG	= 1,
					LANGUAGE_SAGARU		= 1,
					LANGUAGE_CANILUNZT	= 1,
					LANGUAGE_ECUREUILIAN= 1,
					LANGUAGE_DAEMON		= 1,
					LANGUAGE_ENOCHIAN	= 1,
					LANGUAGE_DRUDAKAR	= 1,
					LANGUAGE_TAVAN		= 1
					)
	pto_type = PTO_CIVILIAN

/obj/item/robot_module/robot/clerical/butler
	staffing_role = JOB_BOTANIST
	channels = list(CHANNEL_SERVICE = 1)

/obj/item/robot_module/robot/clerical/butler
	name = "service robot module"

/obj/item/robot_module/robot/clerical/butler/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/gripper/service(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/service(src))
	rel_add(src, nameof(modules), new /obj/item/storage/bag/serviceborg(src))

	var/obj/item/rsf/M = new /obj/item/rsf(src)
	M.stored_matter = 30
	rel_add(src, nameof(modules), M)

	rel_add(src, nameof(modules), new /obj/item/reagent_containers/dropper/industrial(src))

	var/obj/item/flame/lighter/zippo/L = new /obj/item/flame/lighter/zippo(src) // starts unlit: lit, it would burn on the slow lane from module creation
	rel_add(src, nameof(modules), L)

	rel_add(src, nameof(modules), new /obj/item/tray/robotray(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/borghypo/service(src))
	var/obj/item/reagent_containers/food/drinks/bottle/small/beer/PB = new /obj/item/reagent_containers/food/drinks/bottle/small/beer(src)
	rel_add(src, nameof(emag), PB)

	var/datum/reagents/R = new/datum/reagents(50)
	rel_set(PB, nameof(PB.reagents), R)
	rel_set(R, nameof(R.my_atom), PB)
	R.add_reagent(REAGENT_ID_BEER2, 50)
	PB.name = "Auntie Hong's Final Sip"
	PB.desc = "A bottle of very special mix of alcohol and poison. Some may argue that there's alcohol to die for, but Auntie Hong took it to next level."

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/compactor/brewer(src))

	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src)) //Pounce

/obj/item/robot_module/robot/clerical/butler/respawn_consumable(mob/living/silicon/robot/R, amount)
	..()
	var/obj/item/reagent_containers/food/drinks/bottle/small/beer/PB = locate_in_list(src.emag, /obj/item/reagent_containers/food/drinks/bottle/small/beer)
	if(PB)
		PB.reagents.add_reagent(REAGENT_ID_BEER2, 2 * amount)

/obj/item/robot_module/robot/clerical/honkborg
	name = "clown robot module"
	channels = list("Service" = 1,
					"Entertainment" = 1)
	pto_type = PTO_CIVILIAN
	can_be_pushed = 0

/obj/item/robot_module/robot/clerical/honkborg/create_equipment(mob/living/silicon/robot/R)
	rel_add(src, nameof(modules), new /obj/item/gripper/service(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/glass/bucket/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/botanical(src))
	rel_add(src, nameof(modules), new /obj/item/dogborg/pounce(src))
	rel_add(src, nameof(modules), new /obj/item/bikehorn(src))
	rel_add(src, nameof(modules), new /obj/item/gun/launcher/confetti_cannon/robot(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/spray/waterflower(src))

	var/obj/item/rsf/M = new /obj/item/rsf(src)
	M.stored_matter = 30
	rel_add(src, nameof(modules), M)

	rel_add(src, nameof(modules), new /obj/item/reagent_containers/dropper/industrial(src))

	var/obj/item/flame/lighter/zippo/L = new /obj/item/flame/lighter/zippo(src) // starts unlit: lit, it would burn on the slow lane from module creation
	rel_add(src, nameof(modules), L)

	rel_add(src, nameof(modules), new /obj/item/tray/robotray(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/borghypo/service(src))

	var/obj/item/dogborg/sleeper/compactor/honkborg/B = new /obj/item/dogborg/sleeper/compactor/honkborg(src)
	rel_add(src, nameof(modules), B)
	var/obj/item/reagent_containers/spray/LS = new /obj/item/reagent_containers/spray(src)
	rel_add(src, nameof(emag), LS)
	LS.reagents.add_reagent(REAGENT_ID_LUBE, 250)
	LS.name = "Lube spray"
	..()

/obj/item/robot_module/robot/clerical/honkborg/respawn_consumable(mob/living/silicon/robot/R, amount)
	..()
	var/obj/item/reagent_containers/spray/LS = locate_in_list(src.emag, /obj/item/reagent_containers/spray)
	if(LS)
		LS.reagents.add_reagent(REAGENT_ID_LUBE, 2 * amount)

/obj/item/robot_module/robot/clerical/general
	name = "clerical robot module"

/obj/item/robot_module/robot/clerical/general/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/pen/robopen(src))
	rel_add(src, nameof(modules), new /obj/item/form_printer(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/paperwork(src))
	rel_add(src, nameof(modules), new /obj/item/hand_labeler(src))
	rel_add(src, nameof(modules), new /obj/item/stamp(src))
	rel_add(src, nameof(modules), new /obj/item/stamp/denied(src))
	rel_add(src, nameof(emag), new /obj/item/stamp/chameleon(src))
	rel_add(src, nameof(emag), new /obj/item/pen/chameleon(src))

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/compactor/generic(src))
	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src))

/obj/item/robot_module/robot/miner
	staffing_role = DEPARTMENT_CARGO
	name = "miner robot module"
	channels = list(CHANNEL_SUPPLY = 1)
	networks = list(NETWORK_MINE)
	supported_upgrades = list(/obj/item/borg/upgrade/restricted/pka, /obj/item/borg/upgrade/restricted/diamonddrill, /obj/item/borg/upgrade/restricted/adv_scanner, /obj/item/borg/upgrade/restricted/adv_snatcher, /obj/item/borg/upgrade/restricted/adv_mailbag)
	pto_type = PTO_CARGO
	idcard_type = /obj/item/card/id/synthetic/borg

/obj/item/robot_module/robot/miner/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/borg/sight/material(src))
	rel_add(src, nameof(modules), new /obj/item/tool/wrench/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/tool/screwdriver/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/pickaxe/borgdrill(src))
	rel_add(src, nameof(modules), new /obj/item/storage/bag/sheetsnatcher/borg(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/miner(src))
	rel_add(src, nameof(modules), new /obj/item/mining_scanner/robot(src))
	rel_add(src, nameof(modules), new /obj/item/gun/energy/robotic/phasegun(src)) // Phasegun for regular mining cyborg.
	rel_add(src, nameof(modules), new /obj/item/vac_attachment(src))

	var/obj/item/card/id/robot_id = robot.idcard
	robot_id.name = "\improper Synthetic Miner ID"
	robot_id.initial_sprite_stack = list("base-stamp", "top-brown", "stamp-n", "stripe-purple")
	robot_id.reset_icon()
	robot_id.forceMove(src)
	modules |= robot_id // ALLOW(ownership): the robot owns its idcard (robot.idcard); the module only lists it as a usable item
	rel_add(src, nameof(modules), new /obj/item/mail_scanner(src))
	rel_add(src, nameof(modules), new /obj/item/storage/bag/mail/borg(src))
	rel_add(src, nameof(modules), new /obj/item/destTagger(src))
	rel_add(src, nameof(modules), new /obj/item/packageWrap/borg(src))
	rel_add(src, nameof(emag), new /obj/item/kinetic_crusher/machete/dagger(src))

	var/datum/matter_synth/beacon = new /datum/matter_synth/beacon(10000)
	rel_add(src, nameof(synths), beacon)

	var/obj/item/stack/marker_beacon/MB = new /obj/item/stack/marker_beacon(src)
	MB.uses_charge = 1
	MB.charge_costs = list(500)
	rel_add(MB, nameof(MB.synths), beacon)
	rel_add(src, nameof(modules), MB)

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/compactor/supply(src))
	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src))

/obj/item/robot_module/robot/research
	staffing_role = DEPARTMENT_RESEARCH
	name = "research module"
	channels = list(CHANNEL_SCIENCE = 1)
	supported_upgrades = list(/obj/item/borg/upgrade/restricted/advrped, /obj/item/borg/upgrade/restricted/anomalygun)
	pto_type = PTO_SCIENCE

/obj/item/robot_module/robot/research/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/experi_scanner(src))
	rel_add(src, nameof(modules), new /obj/item/robotanalyzer(src))
	rel_add(src, nameof(modules), new /obj/item/card/robot(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/research(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/botanical(src))
	rel_add(src, nameof(modules), new /obj/item/surgical/hemostat/cyborg(src)) //Synth repair
	rel_add(src, nameof(modules), new /obj/item/surgical/surgicaldrill/cyborg(src)) //NIF repair
	rel_add(src, nameof(modules), new /obj/item/surgical/circular_saw/cyborg(src)) // Synth limb replacement
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/syringe(src))
	rel_add(src, nameof(modules), new /obj/item/reagent_containers/glass/beaker/large/borg(src))
	rel_add(src, nameof(modules), new /obj/item/storage/part_replacer(src))
	rel_add(src, nameof(modules), new /obj/item/shockpaddles/robot/jumper(src))
	rel_add(src, nameof(modules), new /obj/item/melee/robotic/baton/slime(src))
	rel_add(src, nameof(modules), new /obj/item/gun/energy/robotic/taser/xeno(src))
	rel_add(src, nameof(modules), new /obj/item/xenoarch_multi_tool(src))
	rel_add(src, nameof(modules), new /obj/item/pickaxe/excavationdrill(src))
	// Anomaly handling
	rel_add(src, nameof(modules), new /obj/item/analyzer(src))
	rel_add(src, nameof(modules), new /obj/item/assembly/signaler(src))
	rel_add(src, nameof(modules), new /obj/item/anomaly_scanner(src))

	rel_add(src, nameof(emag), new /obj/item/hand_tele(src))

	var/datum/matter_synth/nanite = new /datum/matter_synth/nanite(10000)
	rel_add(src, nameof(synths), nanite)
	var/datum/matter_synth/wire = new /datum/matter_synth/wire()						//Added to allow repairs, would rather add cable now than be asked to add it later,
	rel_add(src, nameof(synths), wire) //Cable code, taken from engiborg,

	var/obj/item/stack/nanopaste/N = new /obj/item/stack/nanopaste(src)
	N.uses_charge = 1
	N.charge_costs = list(1000)
	rel_add(N, nameof(N.synths), nanite)
	rel_add(src, nameof(modules), N)

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/compactor/analyzer(src))
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/materials(src))
	rel_add(src, nameof(emag), new /obj/item/dogborg/pounce(src))

/obj/item/robot_module/robot/research/respawn_consumable(mob/living/silicon/robot/R, amount)

	var/obj/item/reagent_containers/syringe/S = locate_in_list(src.modules, /obj/item/reagent_containers/syringe)
	if(S && S.mode == 2)
		S.reagents.clear_reagents()
		S.mode = initial(S.mode)
		S.desc = initial(S.desc)
		S.update_icon()

	..()

/obj/item/robot_module/robot/security/combat
	name = "combat robot module"
	hide_on_manifest = TRUE
	supported_upgrades = list(/obj/item/borg/upgrade/restricted/bellycapupgrade)

/obj/item/robot_module/robot/security/combat/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/handcuffs/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/taperoll/police(src))
	rel_add(src, nameof(modules), new /obj/item/gun/energy/robotic/laser/rifle(src))
	rel_add(src, nameof(modules), new /obj/item/gun/energy/robotic/disabler(src))
	rel_add(src, nameof(modules), new /obj/item/pickaxe/plasmacutter/borg(src))
	rel_add(src, nameof(modules), new /obj/item/melee/robotic/blade/dagger(src))
	rel_add(src, nameof(modules), new /obj/item/borg/combat/shield(src))
	rel_add(src, nameof(modules), new /obj/item/borg/combat/mobility(src))
	rel_add(src, nameof(modules), new /obj/item/melee/robotic/borg_combat_shocker(src))
	rel_add(src, nameof(modules), new /obj/item/ticket_printer(src))
	rel_add(src, nameof(emag), new /obj/item/gun/energy/robotic/laser/heavy(src))

	rel_add(src, nameof(modules), new /obj/item/dogborg/sleeper/K9/ert(src))
	rel_add(src, nameof(modules), new /obj/item/dogborg/pounce(src))

/* Drones */

/obj/item/robot_module/drone
	names_assemblies = TRUE
	name = "drone module"
	hide_on_manifest = TRUE
	no_slip = 1
	networks = list(NETWORK_ENGINEERING)

/// Drones have no belly and can't be ridden.
/obj/item/robot_module/drone/on_robot_equip(mob/living/silicon/robot/robot)
	return

/obj/item/robot_module/drone/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/borg/sight/meson(src))
	rel_add(src, nameof(modules), new /obj/item/weldingtool/electric/mounted/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/tool/screwdriver/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/tool/wrench/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/tool/crowbar/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/tool/wirecutters/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/t_scanner(src))
	rel_add(src, nameof(modules), new /obj/item/multitool/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/lightreplacer(src))
	rel_add(src, nameof(modules), new /obj/item/gripper/drone(src))
	rel_add(src, nameof(modules), new /obj/item/soap(src))
	rel_add(src, nameof(modules), new /obj/item/extinguisher(src))
	rel_add(src, nameof(modules), new /obj/item/pipe_painter(src))
	rel_add(src, nameof(modules), new /obj/item/floor_painter(src))
	rel_add(src, nameof(modules), new /obj/item/pipe_dispenser(src))

	rel_add(src, nameof(modules), new/obj/item/tank/jetpack/carbondioxide(src))

	var/obj/item/pickaxe/plasmacutter/borg/PC = new /obj/item/pickaxe/plasmacutter/borg(src)
	rel_add(src, nameof(emag), PC)
	PC.name = "Plasma Cutter"

	var/datum/matter_synth/metal = new /datum/matter_synth/metal(25000)
	var/datum/matter_synth/glass = new /datum/matter_synth/glass(25000)
	var/datum/matter_synth/wood = new /datum/matter_synth/wood(25000)
	var/datum/matter_synth/plastic = new /datum/matter_synth/plastic(25000)
	var/datum/matter_synth/wire = new /datum/matter_synth/wire(30)
	rel_add(src, nameof(synths), metal)
	rel_add(src, nameof(synths), glass)
	rel_add(src, nameof(synths), wood)
	rel_add(src, nameof(synths), plastic)
	rel_add(src, nameof(synths), wire)

	var/obj/item/matter_decompiler/MD = new /obj/item/matter_decompiler(src)
	rel_set(MD, nameof(MD.metal), metal)
	rel_set(MD, nameof(MD.glass), glass)
	rel_set(MD, nameof(MD.wood), wood)
	rel_set(MD, nameof(MD.plastic), plastic)
	rel_add(src, nameof(modules), new /obj/item/robotic_multibelt/materials(src))
	rel_add(src, nameof(modules), MD)

/obj/item/robot_module/drone/construction
	name = "construction drone module"
	hide_on_manifest = TRUE
	channels = list(CHANNEL_ENGINEERING = 1)
	languages = list()

/obj/item/robot_module/drone/construction/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/rcd/electric/mounted/borg/lesser(src))

/obj/item/robot_module/drone/respawn_consumable(mob/living/silicon/robot/R, amount)
	var/obj/item/lightreplacer/LR = locate_in_list(src.modules, /obj/item/lightreplacer)
	LR?.Charge(R, amount)
	..()
	return

/obj/item/robot_module/drone/mining
	name = "miner drone module"
	channels = list(CHANNEL_SUPPLY = 1)
	networks = list(NETWORK_MINE)

/obj/item/robot_module/drone/mining/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/borg/sight/material(src))
	rel_add(src, nameof(modules), new /obj/item/pickaxe/borgdrill(src))
	rel_add(src, nameof(modules), new /obj/item/ore_bag(src))
	rel_add(src, nameof(modules), new /obj/item/storage/bag/sheetsnatcher/borg(src))
	rel_add(src, nameof(modules), new /obj/item/gun/energy/robotic/phasegun(src)) // makes the mining borg able to defend itself.
	rel_add(src, nameof(emag), new /obj/item/pickaxe/diamonddrill(src))

/obj/item/robot_module/drone/talon
	name = "talon drone module"
	idcard_type = /obj/item/card/id/talon
	channels = list(CHANNEL_TALON = 1)
	networks = list(NETWORK_TALON_SHIP)
