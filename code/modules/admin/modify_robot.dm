ADMIN_VERB_AND_CONTEXT_MENU(modify_robot, R_ADMIN|R_FUN|R_VAREDIT|R_EVENT, "Modify Robot", "Allows to add or remove modules to/from robots.", ADMIN_CATEGORY_SILICON, mob/living/silicon/robot/target in REGISTRY_MEMBERS(REGISTRY_SILICONS))
	if(!target)
		return
	var/datum/eventkit/modify_robot/modify_robot = new()
	modify_robot.target_handle = om_handle(target)
	modify_robot.selected_ai = target.is_slaved()
	modify_robot.tgui_interact(user.mob)

/datum/eventkit/modify_robot
	var/tmp/target_handle
	var/mob/living/silicon/robot/source
	var/selected_ai
	var/ion_law	= "IonLaw"
	var/zeroth_law = "ZerothLaw"
	var/inherent_law = "InherentLaw"
	var/supplied_law = "SuppliedLaw"
	var/supplied_law_position = MIN_SUPPLIED_LAW_NUMBER
	var/list/datum/ai_laws/law_list
	var/tmp/multibelt_holder_handle	//Currently selected multibelt.

/datum/eventkit/modify_robot/New()
	. = ..()
	log_and_message_admins("has used modify robot and is modifying [target()]")
	law_list = new()
	init_subtypes(/datum/ai_laws, law_list)
	law_list = dd_sortedObjectList(law_list)

/datum/eventkit/modify_robot/tgui_close()
	target_handle = null
	if(source)
		qdel(source)

DECLARE_UI(/datum/eventkit/modify_robot, "ModifyRobot", UI_TITLE("Modify Robot"))

DECLARE_REF(/datum/eventkit/modify_robot, "source", OWNED, null)

/datum/eventkit/modify_robot/ui_assets(mob/user)
	if(!target())
		return list()
	var/datum/asset/spritesheet_batched/robot_icons/spritesheet = GLOB.robot_sprite_sheets[target().modtype]
	return spritesheet ? list(spritesheet) : list()

/datum/eventkit/modify_robot/tgui_data(mob/user)
	. = list()
	// Target section for general data
	var/datum/asset/spritesheet_batched/robot_icons/spritesheet = target() ? GLOB.robot_sprite_sheets[target().modtype] : null

	if(target())
		.["theme"] = target().get_ui_theme()
		.["target"] = list()
		.["target"]["name"] = target().name
		.["target"]["ckey"] = target().ckey
		.["target"]["module"] = target().module
		.["target"]["emagged"] = target().emagged
		.["target"]["crisis_override"] = target().crisis_override
		.["target"]["active_restrictions"] = target().restrict_modules_to
		var/list/possible_restrictions = list()
		for(var/entry in GLOB.robot_modules)
			if(!(target().restrict_modules_to?.Find(entry)))
				possible_restrictions += entry
		.["target"]["possible_restrictions"] = possible_restrictions
		// Target section for options once a module has been selected
		if(target().module)
			.["target"]["active"] = target().icon_selected
			.["target"]["sprite"] = sanitize_css_class_name("[target().sprite_datum.type]")
			.["target"]["sprite_size"] = spritesheet?.icon_size_id(.["target"]["sprite"] + "S")
			.["target"]["modules"] = get_target_items(user)
			var/list/module_options = list()
			for(var/module in GLOB.robot_modules)
				module_options += module
			.["model_options"] = module_options
			// Data for the upgrade options
			.["target"] += get_upgrades()
			var/obj/item/gun/energy/kinetic_accelerator/kin = locate_in_list(target().module.modules, /obj/item/gun/energy/kinetic_accelerator)
			if(kin)
				.["target"]["pka"] += get_pka(kin)
			for(var/obj/item/robotic_multibelt/multibelt in target().module.modules)
				.["target"]["multibelt"] += list(get_mult_belt(multibelt))

			// Radio section
			var/list/radio_channels = list()
			for(var/channel in target().radio.channels)
				radio_channels += channel
			var/list/availalbe_channels = list()
			for(var/channel in (GLOB.radiochannels - target().radio.channels))
				availalbe_channels += channel
			.["target"]["radio_channels"] = radio_channels
			.["target"]["availalbe_channels"] = availalbe_channels
			// Components
			.["target"]["components"] = get_components()
			.["cell"] = list("name" = target().cell?.name, "charge" = target().cell?.charge, "maxcharge" = target().cell?.maxcharge)
			.["cell_options"] = get_cells()
			.["camera_options"] = get_component("camera")
			.["radio_options"] = get_component("radio")
			.["actuator_options"] = get_component("actuator")
			.["diagnosis_options"] = get_component("diagnosis")
			.["comms_options"] = get_component("comms")
			.["armour_options"] = get_component("armour")
			.["current_gear"] = get_gear()
			// Access
			.["id_icon"] = icon2html(target().idcard, user, sourceonly=TRUE)
			var/list/active_access = list()
			for(var/access in target().idcard?.GetAccess())
				active_access += list(list("id" = access, "name" = SSaccess.get_access_desc(access)))
			.["target"]["active_access"] = active_access
			var/list/access_options = list()
			for(var/datum/access/acc)
				if(acc.id in target().idcard?.GetAccess())
					continue
				access_options += list(list("id" = acc.id, "name" = acc.desc))
			.["access_options"] = access_options
			// Section for source data for the module we might want to salvage
			if(source)
				.["source"] += get_module_source(user, spritesheet)
	var/list/all_robots = list()
	for(var/mob/living/silicon/robot/R in REGISTRY_MEMBERS(REGISTRY_SILICONS))
		if(!R.loc)
			continue
		all_robots += list(list("displayText" = "[R]", "value" = "\ref[R]"))
	.["all_robots"] = all_robots
	// Law data
	.["ion_law_nr"] = ionnum()
	.["ion_law"] = ion_law
	.["zeroth_law"] = zeroth_law
	.["inherent_law"] = inherent_law
	.["supplied_law"] = supplied_law
	.["supplied_law_position"] = supplied_law_position

	package_laws(., "zeroth_laws", list(target().laws.zeroth_law))
	package_laws(., "ion_laws", target().laws.ion_laws)
	package_laws(., "inherent_laws", target().laws.inherent_laws)
	package_laws(., "supplied_laws", target().laws.supplied_laws)

	.["isAI"] = isAI(target())
	.["isMalf"] = is_malf(user)
	.["isSlaved"] = target().is_slaved()
	var/list/active_ais = list()
	for(var/mob/living/silicon/ai/ai in active_ais())
		if(!ai.loc)
			continue
		active_ais += list(list("displayText" = "[ai]", "value" = "\ref[ai]"))
	.["active_ais"] = active_ais
	.["selected_ai"] = selected_ai ? selected_ai : null

	var/list/channels = list()
	for(var/ch_name in target().law_channels())
		channels[++channels.len] = list("channel" = ch_name)
	.["channel"] = target().lawchannel
	.["channels"] = channels
	.["law_sets"] = package_multiple_laws(law_list)

/datum/eventkit/modify_robot/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_EVENT|R_DEBUG)

UI_ACT(/datum/eventkit/modify_robot, "rename", ui_act_rename, UI_ARG_VALUE("new_name"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_rename)
	target().name = params["new_name"]
	target().custom_name = params["new_name"]
	target().real_name = params["new_name"]
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "select_target", ui_act_select_target, UI_ARG_REF("new_target", null))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_select_target)
	var/new_target = params["new_target"]
	if(new_target != target())
		target_handle = om_handle(params["new_target"])
		log_and_message_admins("changed robot modifictation target to [target()]")
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "toggle_crisis", ui_act_toggle_crisis)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_toggle_crisis)
	target().crisis_override = !target().crisis_override
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "add_restriction", ui_act_add_restriction, UI_ARG_VALUE("new_restriction"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_add_restriction)
	var/new_restriction = params["new_restriction"]
	if(!(new_restriction in GLOB.robot_modules))
		return FALSE
	LAZYOR(target().restrict_modules_to, new_restriction)
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "remove_restriction", ui_act_remove_restriction, UI_ARG_VALUE("rem_restriction"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_remove_restriction)
	var/rem_restriction = params["rem_restriction"]
	if(!(rem_restriction in GLOB.robot_modules))
		return FALSE
	LAZYREMOVE(target().restrict_modules_to, rem_restriction)
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "select_source", ui_act_select_source, UI_ARG_VALUE("new_source"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_select_source)
	if(source)
		qdel(source)
	var/module_type = GLOB.robot_modules[params["new_source"]]
	if(ispath(module_type, /obj/item/robot_module/robot/syndicate))
		source = new /mob/living/silicon/robot/syndicate(null)
	else if(ispath(module_type, /obj/item/robot_module/robot/malf))
		source = new /mob/living/silicon/robot/malf(null)
	else
		source = new /mob/living/silicon/robot(null)
	source.modtype = params["new_source"]
	var/obj/item/robot_module/robot/robot_type = new module_type(source)
	source.sprite_datum = pick(SSrobot_sprites.get_module_sprites(source.modtype, source))
	source.update_icon()
	source.emag_items = TRUE
	if(!istype(robot_type, /obj/item/robot_module/robot))
		QDEL_NULL(source)
		return TRUE
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "reset_module", ui_act_reset_module)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_reset_module)
	target().module_reset(FALSE)
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "add_module", ui_act_add_module, UI_ARG_REF("module", null, /obj/item))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_add_module)
	var/obj/item/selected_item = params["module"]
	if(!selected_item)
		return TRUE
	if(istype(selected_item, /obj/item/card/id))
		source.idcard = null
	source.module.emag -= selected_item
	source.module.modules -= selected_item
	target().module.add_item(selected_item, target())
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "rem_module", ui_act_rem_module, UI_ARG_REF("module", null, /obj/item))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_rem_module)
	var/obj/item/rem_item = params["module"]
	if(target().idcard == rem_item)
		target().idcard = new /obj/item/card/id/synthetic(target())
	target().uneq_all()
	target().hud_used?.update_robot_modules_display(TRUE)
	target().module.emag.Remove(rem_item)
	target().module.modules.Remove(rem_item)
	rem_item.moveToNullspace()
	target().hud_used?.update_robot_modules_display()
	qdel(rem_item)
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "swap_module", ui_act_swap_module)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_swap_module)
	if(!source)
		return FALSE
	var/mod_type = source.modtype
	qdel(source.module)
	var/module_type = GLOB.robot_modules[target().modtype]
	source.modtype = target().modtype
	new module_type(source)
	source.sprite_datum = target().sprite_datum
	source.update_icon()
	source.emag_items = TRUE
	// Target
	target().uneq_all()
	target().hud_used?.update_robot_modules_display(TRUE)
	qdel(target().module)
	target().modtype = mod_type
	module_type = GLOB.robot_modules[mod_type]
	target().transform_with_anim()
	new module_type(target())
	target().hands.icon_state = target().get_hud_module_icon()
	target().hud_used?.update_robot_modules_display()
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "ert_toggle", ui_act_ert_toggle)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_ert_toggle)
	target().crisis_override = !target().crisis_override
	target().module_reset(FALSE)
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "add_compatibility", ui_act_add_compatibility, UI_ARG_PATH("upgrade", /datum))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_add_compatibility)
	LAZYOR(target().module.supported_upgrades, params["upgrade"])
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "rem_compatibility", ui_act_rem_compatibility, UI_ARG_PATH("upgrade", /datum))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_rem_compatibility)
	LAZYREMOVE(target().module.supported_upgrades, params["upgrade"])
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "add_upgrade", ui_act_add_upgrade, UI_ARG_PATH("upgrade", /datum))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_add_upgrade)
	var/new_upgrade = params["upgrade"]
	if(new_upgrade == /obj/item/borg/upgrade/utility/reset)
		var/obj/item/borg/upgrade/utility/reset/rmodul = new_upgrade
		var/sure = act_ask(ui.user, action, params, ui, "reset", /datum/om/prompt/choice/alert, message = "Are you sure that you want to install [initial(rmodul.name)] and reset the robot's module?", title = "Confirm", choices = list("Yes","No"))
		if(sure != "Yes")
			return FALSE
	var/new_name
	if(new_upgrade == /obj/item/borg/upgrade/utility/rename)
		var/obj/item/borg/upgrade/utility/rename/renamer = new_upgrade
		new_name = act_ask(ui.user, action, params, ui, "name", /datum/om/prompt/text, message = "Enter new robot name", title = "Robot Reclassification", default = initial(renamer.heldname), max_length = MAX_NAME_LEN, encode = FALSE)
		if(isnull(new_name))
			return FALSE
	var/obj/item/borg/upgrade/U = new new_upgrade(null)
	if(new_upgrade == /obj/item/borg/upgrade/utility/rename)
		var/obj/item/borg/upgrade/utility/rename/UN = U
		new_name = sanitizeSafe(new_name, MAX_NAME_LEN)
		if(new_name)
			UN.heldname = new_name
		U = UN
	if(istype(U, /obj/item/borg/upgrade/restricted))
		LAZYOR(target().module.supported_upgrades, new_upgrade)
	if(!U.action(ui.user, target()))
		return FALSE
	U.forceMove(target())
	target().hud_used?.update_robot_modules_display()
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "install_modkit", ui_act_install_modkit, UI_ARG_PATH("modkit", /datum))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_install_modkit)
	var/new_modkit = params["modkit"]
	var/obj/item/gun/energy/kinetic_accelerator/kin = locate_in_list(target().module.modules, /obj/item/gun/energy/kinetic_accelerator)
	var/obj/item/borg/upgrade/modkit/M = new new_modkit(null)
	M.install(kin, target())
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "remove_modkit", ui_act_remove_modkit, UI_ARG_REF("modkit", null, /obj/item))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_remove_modkit)
	var/obj/item/gun/energy/kinetic_accelerator/kin = locate_in_list(target().module.modules, /obj/item/gun/energy/kinetic_accelerator)
	var/obj/item/rem_kit = params["modkit"]
	LAZYREMOVE(kin.modkits, rem_kit)
	qdel(rem_kit)
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "select_multibelt", ui_act_select_multibelt, UI_ARG_REF("multibelt", null))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_select_multibelt)
	multibelt_holder_handle = om_handle(params["multibelt"])
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "install_tool", ui_act_install_tool, UI_ARG_PATH("tool", /datum))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_install_tool)
	if(!istype(multibelt_holder(), /obj/item/robotic_multibelt))
		return FALSE
	if(istype(multibelt_holder(), /obj/item/robotic_multibelt/materials))
		target().add_new_material(params["tool"])
		return TRUE
	var/new_tool = params["tool"]
	if(new_tool in GLOB.all_borg_multitool_options)
		multibelt_holder().cyborg_integrated_tools += new_tool //Make sure you don't add items directly to it, or you can't ever remove them.
		multibelt_holder().generate_tools()
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "remove_tool", ui_act_remove_tool, UI_ARG_REF("tool", null, /datum/matter_synth))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_remove_tool)
	if(!istype(multibelt_holder(), /obj/item/robotic_multibelt))
		return FALSE
	if(istype(multibelt_holder(), /obj/item/robotic_multibelt/materials))
		var/datum/matter_synth/synth = params["tool"]
		target().module.synths -= synth
		qdel(synth)
		target().update_material_multibelts()
		return TRUE
	var/obj/item/rem_tool = params["tool"]
	if(multibelt_holder().selected_item == rem_tool)
		multibelt_holder().dropped() //Reset to original icon.
	rem_tool.moveToNullspace()
	multibelt_holder().cyborg_integrated_tools -= rem_tool.type
	multibelt_holder().integrated_tools_by_name -= rem_tool.name
	multibelt_holder().integrated_tool_images -= rem_tool.name
	qdel(rem_tool)
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "add_channel", ui_act_add_channel, UI_ARG_TEXT("channel"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_add_channel)
	var/selected_radio_channel = params["channel"]
	if(selected_radio_channel == CHANNEL_SPECIAL_OPS || selected_radio_channel == CHANNEL_RESPONSE_TEAM)
		target().radio.centComm = 1
	if(selected_radio_channel == CHANNEL_RAIDER)
		qdel(target().radio.keyslot)
		target().radio.keyslot = new /obj/item/encryptionkey/raider(target())
		target().radio.syndie = 1
	if(selected_radio_channel == CHANNEL_MERCENARY)
		qdel(target().radio.keyslot)
		target().radio.keyslot = new /obj/item/encryptionkey/syndicate(target())
		target().radio.syndie = 1
	target().module.channels += list("[selected_radio_channel]" = 1)
	target().radio.channels[selected_radio_channel] = target().module.channels[selected_radio_channel]
	target().radio.secure_radio_connections[selected_radio_channel] = GLOB.radio_service.add_object(target().radio, GLOB.radiochannels[selected_radio_channel],  RADIO_CHAT)
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "rem_channel", ui_act_rem_channel, UI_ARG_VALUE("channel"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_rem_channel)
	var/selected_radio_channel = params["channel"]
	if((selected_radio_channel == CHANNEL_SPECIAL_OPS || selected_radio_channel == CHANNEL_RESPONSE_TEAM) && !(target().module.channels[CHANNEL_SPECIAL_OPS] || target().module.channels[CHANNEL_RESPONSE_TEAM]))
		target().radio.centComm = 0
	target().module.channels -= selected_radio_channel
	if((selected_radio_channel == CHANNEL_MERCENARY || selected_radio_channel == CHANNEL_RAIDER) && !(target().module.channels[CHANNEL_RAIDER] || target().module.channels[CHANNEL_MERCENARY]))
		qdel(target().radio.keyslot)
		target().radio.keyslot = null
		target().radio.syndie = 0
	target().radio.channels = list()
	for(var/n_chan in target().module.channels)
		target().radio.channels[n_chan] = target().module.channels[n_chan]
	GLOB.radio_service.remove_object(target().radio, GLOB.radiochannels[selected_radio_channel])
	target().radio.secure_radio_connections -= selected_radio_channel
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "add_component", ui_act_add_component, UI_ARG_REF("component", "proc:ui_source_target_components", /datum/robot_component), UI_ARG_PATH("new_part", /datum))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_add_component)
	var/datum/robot_component/C = params["component"]
	if(!C || C.internal)
		return FALSE
	var/new_component = params["new_part"]
	if(C.slot == ROBOT_SLOT_POWER)
		if(!ispath(new_component, /obj/item/cell))
			return FALSE
		qdel(target().remove_cell())
		target().set_cell(new new_component(target()))
		return TRUE
	if(!ispath(new_component, C.external_type))
		new_component = C.external_type
	if(C.wrapped)
		qdel(C.uninstall())
	C.clear_located_damage()
	C.install(new new_component(target()))
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "rem_component", ui_act_rem_component, UI_ARG_REF("component", "proc:ui_source_target_components", /datum/robot_component))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_rem_component)
	var/datum/robot_component/C = params["component"]
	if(!C?.wrapped || C.internal)
		return FALSE
	if(C.slot == ROBOT_SLOT_POWER)
		qdel(target().remove_cell())
		return TRUE
	qdel(C.uninstall())
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "adjust_cell_charge", ui_act_adjust_cell_charge, UI_ARG_NUM("charge"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_adjust_cell_charge)
	var/obj/item/cell/cell = target().cell
	if(!cell)
		return FALSE
	var/delta = clamp(params["charge"], 0, cell.maxcharge) - cell.charge
	if(delta > 0)
		target().add_power(ROBOT_CELL_JOULES(delta), src)
	else if(delta < 0)
		target().draw_power(ROBOT_CELL_JOULES(-delta), src, 0, TRUE)
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "adjust_brute", ui_act_adjust_brute, UI_ARG_REF("component", "proc:ui_source_target_components", /datum/robot_component), UI_ARG_NUM("damage"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_adjust_brute)
	var/datum/robot_component/C = params["component"]
	if(!C)
		return FALSE
	C.set_located_damage(params["damage"], C.get_wiring_damage())
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "adjust_electronics", ui_act_adjust_electronics, UI_ARG_REF("component", "proc:ui_source_target_components", /datum/robot_component), UI_ARG_NUM("damage"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_adjust_electronics)
	var/datum/robot_component/C = params["component"]
	if(!C)
		return FALSE
	C.set_located_damage(C.get_structural_damage(), params["damage"])
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "add_access", ui_act_add_access, UI_ARG_NUM("access"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_add_access)
	target().idcard.access += params["access"]
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "rem_access", ui_act_rem_access, UI_ARG_NUM("access"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_rem_access)
	target().idcard.access -= params["access"]
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "add_centcom", ui_act_add_centcom)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_add_centcom)
	target().idcard.access |= SSaccess.get_all_centcom_access()
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "rem_centcom", ui_act_rem_centcom)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_rem_centcom)
	target().idcard.access -= SSaccess.get_all_centcom_access()
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "add_station", ui_act_add_station)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_add_station)
	target().idcard.access |= SSaccess.get_all_station_access()
	target().idcard.access |= ACCESS_SYNTH
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "rem_station", ui_act_rem_station)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_rem_station)
	target().idcard.access -= SSaccess.get_all_station_access()
	target().idcard.access -= ACCESS_SYNTH
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "law_channel", ui_act_law_channel, UI_ARG_VALUE("law_channel"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_law_channel)
	if(params["law_channel"] in target().law_channels())
		target().lawchannel = params["law_channel"]
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "state_law", ui_act_state_law, UI_ARG_REF("ref", "proc:ui_source_target_laws_all_laws", /datum/ai_law), UI_ARG_NUM("state_law"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_state_law)
	var/datum/ai_law/AL = params["ref"]
	if(AL)
		var/state_law = params["state_law"]
		target().laws.set_state_law(AL, state_law)
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "add_zeroth_law", ui_act_add_zeroth_law)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_add_zeroth_law)
	if(zeroth_law && !target().laws.zeroth_law)
		target().set_zeroth_law(zeroth_law)
		target().lawsync()
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "add_ion_law", ui_act_add_ion_law)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_add_ion_law)
	if(ion_law)
		target().add_ion_law(ion_law)
		target().lawsync()
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "add_inherent_law", ui_act_add_inherent_law)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_add_inherent_law)
	if(inherent_law)
		target().add_inherent_law(inherent_law)
		target().lawsync()
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "add_supplied_law", ui_act_add_supplied_law)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_add_supplied_law)
	if(supplied_law && supplied_law_position >= 1 && MIN_SUPPLIED_LAW_NUMBER <= MAX_SUPPLIED_LAW_NUMBER)
		target().add_supplied_law(supplied_law_position, supplied_law)
		target().lawsync()
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "change_zeroth_law", ui_act_change_zeroth_law, UI_ARG_TEXT("val"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_change_zeroth_law)
	var/new_law = sanitize(params["val"])
	if(new_law && new_law != zeroth_law)
		zeroth_law = new_law
		target().lawsync()
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "change_ion_law", ui_act_change_ion_law, UI_ARG_TEXT("val"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_change_ion_law)
	var/new_law = sanitize(params["val"])
	if(new_law && new_law != ion_law)
		ion_law = new_law
		target().lawsync()
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "change_inherent_law", ui_act_change_inherent_law, UI_ARG_TEXT("val"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_change_inherent_law)
	var/new_law = sanitize(params["val"])
	if(new_law && new_law != inherent_law)
		inherent_law = new_law
		target().lawsync()
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "change_supplied_law", ui_act_change_supplied_law, UI_ARG_TEXT("val"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_change_supplied_law)
	var/new_law = sanitize(params["val"])
	if(new_law && new_law != supplied_law)
		supplied_law = new_law
		target().lawsync()
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "change_supplied_law_position", ui_act_change_supplied_law_position)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_change_supplied_law_position)
	var/new_position = act_ask(ui.user, action, params, ui, "position", /datum/om/prompt/number, message = "Enter new supplied law position between 1 and [MAX_SUPPLIED_LAW_NUMBER], inclusive. Inherent laws at the same index as a supplied law will not be stated.", title = "Law Position", default = supplied_law_position, max = MAX_SUPPLIED_LAW_NUMBER, min = 1)
	if(isnum(new_position))
		supplied_law_position = CLAMP(new_position, 1, MAX_SUPPLIED_LAW_NUMBER)
		target().lawsync()
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "edit_law", ui_act_edit_law, UI_ARG_REF("edit_law", "proc:ui_source_target_laws_all_laws", /datum/ai_law))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_edit_law)
	var/datum/ai_law/AL = params["edit_law"]
	if(AL)
		var/new_law = act_ask(ui.user, action, params, ui, "law", /datum/om/prompt/text, message = "Enter new law. Leaving the field blank will cancel the edit.", title = "Edit Law", default = AL.law)
		if(new_law && new_law != AL.law)
			AL.law = new_law
			target().lawsync()
		return TRUE

UI_ACT(/datum/eventkit/modify_robot, "delete_law", ui_act_delete_law, UI_ARG_REF("delete_law", "proc:ui_source_target_laws_all_laws", /datum/ai_law))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_delete_law)
	var/datum/ai_law/AL = params["delete_law"]
	if(AL)
		target().delete_law(AL)
		target().lawsync()
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "state_laws", ui_act_state_laws)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_state_laws)
	target().statelaws(target().laws)
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "state_law_set", ui_act_state_law_set, UI_ARG_REF("state_law_set", "law_list", /datum/ai_laws))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_state_law_set)
	var/datum/ai_laws/ALs = params["state_law_set"]
	if(ALs)
		target().statelaws(ALs)
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "transfer_laws", ui_act_transfer_laws, UI_ARG_REF("transfer_laws", "law_list", /datum/ai_laws))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_transfer_laws)
	var/datum/ai_laws/ALs = params["transfer_laws"]
	if(ALs)
		ALs.sync(target(), 0)
		target().lawsync()
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "notify_laws", ui_act_notify_laws)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_notify_laws)
	to_chat(target(), span_danger("Law Notice\n") + target().laws.get_formatted_laws())
	if(isAI(target()))
		var/mob/living/silicon/ai/our_ai = target()
		for(var/mob/living/silicon/robot/R in our_ai.connected_robots)
			to_chat(R, span_danger("Law Notice\n") + R.laws.get_formatted_laws())
	if(ui.user != target())
		to_chat(ui.user, span_notice("Laws displayed."))
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "select_ai", ui_act_select_ai, UI_ARG_VALUE("new_ai"))
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_select_ai)
	selected_ai = params["new_ai"]
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "swap_sync", ui_act_swap_sync)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_swap_sync)
	var/mob/living/silicon/ai/our_ai
	for(var/mob/living/silicon/ai/ai in REGISTRY_MEMBERS(REGISTRY_AIS))
		if(ai.name == selected_ai)
			our_ai = ai
			break
	if(!our_ai)
		our_ai = select_active_ai_with_fewest_borgs()
	if(our_ai)
		target().lawupdate = TRUE
		target().connect_to_ai(our_ai)
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "disconnect_ai", ui_act_disconnect_ai)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_disconnect_ai)
	if(target().is_slaved())
		target().disconnect_from_ai()
		target().lawupdate = FALSE
	return TRUE

UI_ACT(/datum/eventkit/modify_robot, "toggle_emag", ui_act_toggle_emag)
UI_ACT_PROC(/datum/eventkit/modify_robot, ui_act_toggle_emag)
	if(target().emagged)
		target().emagged = FALSE
		target().clear_supplied_laws()
		target().clear_inherent_laws()
		target().laws = new using_map.default_law_type
		to_chat(target(), span_danger("Laws updated!\n") + target().laws.get_formatted_laws())
		target().hud_used?.update_robot_modules_display()
	else
		target().emagged = TRUE
		target().lawupdate = FALSE
		target().disconnect_from_ai()
		target().clear_supplied_laws()
		target().clear_inherent_laws()
		target().laws = new /datum/ai_laws/syndicate_override
		if(target().bolt)
			if(!target().bolt.malfunction)
				target().bolt.malfunction = MALFUNCTION_PERMANENT
		to_chat(target(), span_danger("Laws updated!\n") + target().laws.get_formatted_laws())
		target().hud_used?.update_robot_modules_display()
	return TRUE

/// The list the UI_ARG_REF rows resolve refs in.
/datum/eventkit/modify_robot/proc/ui_source_target_components()
	return target().components

/// The list the UI_ARG_REF rows resolve refs in.
/datum/eventkit/modify_robot/proc/ui_source_target_laws_all_laws()
	return target().laws.all_laws()

/datum/eventkit/modify_robot/proc/get_target_items(mob/user)
	var/list/target_items = list()
	for(var/obj/item in target().module.modules)
		target_items += list(list("name" = item.name, "ref" = "\ref[item]", "icon" = icon2html(item, user, sourceonly=TRUE), "desc" = item.desc))
	return target_items

/datum/eventkit/modify_robot/proc/get_module_source(mob/user, datum/asset/spritesheet_batched/robot_icons/spritesheet)
	var/list/source_list = list()
	source_list["model"] = source.module
	source_list["sprite"] = sanitize_css_class_name("[source.sprite_datum.type]")
	source_list["sprite_size"] = spritesheet?.icon_size_id(source_list["sprite"] + "S")
	var/list/source_items = list()
	for(var/obj/item in (source.module.modules | source.module.emag))
		var/exists
		for(var/obj/has_item in (target().module.modules + target().module.emag))
			if(has_item.name == item.name)
				exists = TRUE
				break
		if(exists)
			continue
		source_items += list(list("name" = item.name, "ref" = "\ref[item]", "icon" = icon2html(item, user, sourceonly=TRUE), "desc" = item.desc))
	source_list["modules"] = source_items
	return source_list

/datum/eventkit/modify_robot/proc/get_upgrades()
	var/list/all_upgrades = list()
	var/list/whitelisted_upgrades = list()
	var/list/blacklisted_upgrades = list()
	for(var/datum/design_techweb/prosfab/robot_upgrade/restricted/upgrade as anything in subtypesof(/datum/design_techweb/prosfab/robot_upgrade/restricted))
		if(!upgrade.name)
			continue
		if(!(initial(upgrade.build_path) in target().module.supported_upgrades))
			whitelisted_upgrades += list(list("name" = initial(upgrade.name), "path" = "[initial(upgrade.build_path)]"))
		else
			blacklisted_upgrades += list(list("name" = initial(upgrade.name), "path" = "[initial(upgrade.build_path)]"))
	all_upgrades["whitelisted_upgrades"] = whitelisted_upgrades
	all_upgrades["blacklisted_upgrades"] = blacklisted_upgrades
	var/list/utility_upgrades = list()
	for(var/datum/design_techweb/prosfab/robot_upgrade/utility/upgrade as anything in subtypesof(/datum/design_techweb/prosfab/robot_upgrade/utility))
		if(!upgrade.name)
			continue
		if(!(robot_upgrade_prototype(initial(upgrade.build_path))?.is_installed(target())))
			utility_upgrades += list(list("name" = initial(upgrade.name), "path" = "[initial(upgrade.build_path)]"))
	all_upgrades["utility_upgrades"] = utility_upgrades
	var/list/basic_upgrades = list()
	for(var/datum/design_techweb/prosfab/robot_upgrade/basic/upgrade as anything in subtypesof(/datum/design_techweb/prosfab/robot_upgrade/basic))
		if(!upgrade.name)
			continue
		if(!(robot_upgrade_prototype(initial(upgrade.build_path))?.is_installed(target())))
			basic_upgrades += list(list("name" = initial(upgrade.name), "path" = "[initial(upgrade.build_path)]", "installed" = 0))
		else
			basic_upgrades += list(list("name" = initial(upgrade.name), "path" = "[initial(upgrade.build_path)]", "installed" = 1))
	all_upgrades["basic_upgrades"] = basic_upgrades
	var/list/advanced_upgrades = list()
	for(var/datum/design_techweb/prosfab/robot_upgrade/advanced/upgrade as anything in subtypesof(/datum/design_techweb/prosfab/robot_upgrade/advanced))
		if(!upgrade.name)
			continue
		if(!(robot_upgrade_prototype(initial(upgrade.build_path))?.is_installed(target())))
			advanced_upgrades += list(list("name" = initial(upgrade.name), "path" = "[initial(upgrade.build_path)]", "installed" = 0))
		else
			advanced_upgrades += list(list("name" = initial(upgrade.name), "path" = "[initial(upgrade.build_path)]", "installed" = 1))
	all_upgrades["advanced_upgrades"] = advanced_upgrades
	var/list/restricted_upgrades = list()
	for(var/datum/design_techweb/prosfab/robot_upgrade/restricted/upgrade as anything in subtypesof(/datum/design_techweb/prosfab/robot_upgrade/restricted))
		if(!upgrade.name)
			continue
		if(!(robot_upgrade_prototype(initial(upgrade.build_path))?.is_installed(target())))
			if(!(initial(upgrade.build_path) in target().module.supported_upgrades))
				restricted_upgrades += list(list("name" = initial(upgrade.name), "path" = "[initial(upgrade.build_path)]", "installed" = 2))
				continue
			restricted_upgrades += list(list("name" = initial(upgrade.name), "path" = "[initial(upgrade.build_path)]", "installed" = 0))
		else
			restricted_upgrades += list(list("name" = initial(upgrade.name), "path" = "[initial(upgrade.build_path)]", "installed" = 1))
	all_upgrades["restricted_upgrades"] = restricted_upgrades
	return all_upgrades

/datum/eventkit/modify_robot/proc/get_pka(obj/item/gun/energy/kinetic_accelerator/kin)
	var/list/pka = list()
	pka["name"] = kin.name
	var/list/installed_modkits = list()
	for(var/obj/item/borg/upgrade/modkit/modkit in kin.modkits)
		installed_modkits += list(list("name" = modkit.name, "ref" = "\ref[modkit]", "costs" = modkit.cost))
	pka["installed_modkits"] = installed_modkits
	var/list/modkits = list()
	for(var/modkit in typesof(/obj/item/borg/upgrade/modkit))
		var/obj/item/borg/upgrade/modkit/single_modkit = modkit
		if(single_modkit == /obj/item/borg/upgrade/modkit)
			continue
		if(kin.get_remaining_mod_capacity() < initial(single_modkit.cost))
			modkits += list(list("name" = initial(single_modkit.name), "path" = single_modkit, "costs" = initial(single_modkit.cost), "denied" = TRUE, "denied_by" = "Insufficient capacity!"))
			continue
		if(initial(single_modkit.denied_type))
			var/number_of_denied = 0
			var/denied = FALSE
			for(var/A in kin.get_modkits())
				var/obj/item/borg/upgrade/modkit/M = A
				if(istype(M, initial(single_modkit.denied_type)))
					number_of_denied++
				if(number_of_denied >= initial(single_modkit.maximum_of_type))
					var/obj/item/denied_type = initial(single_modkit.denied_type)
					modkits += list(list("name" = initial(single_modkit.name), "path" = single_modkit, "costs" = initial(single_modkit.cost), "denied" = TRUE, "denied_by" = "[initial(denied_type.name)]"))
					denied = TRUE
					break
			if(denied)
				continue
		modkits += list(list("name" = initial(single_modkit.name), "path" = single_modkit, "costs" = initial(single_modkit.cost)))
	pka["modkits"] = modkits
	pka["capacity"] = kin.get_remaining_mod_capacity()
	pka["max_capacity"] = kin.max_mod_capacity
	return pka

/datum/eventkit/modify_robot/proc/get_mult_belt(obj/item/robotic_multibelt/mult_belt)
	var/list/multi_belt_list = list()
	multi_belt_list["name"] = mult_belt.name
	multi_belt_list["ref"] = REF(mult_belt)
	var/list/integrated_tools = list()
	var/list/tools = list()
	if(istype(mult_belt, /obj/item/robotic_multibelt/materials))
		for(var/datum/matter_synth/synth in target().module.synths)
			integrated_tools += list(list("name" = synth.name, "ref" = "\ref[synth]"))
		for(var/tool in GLOB.material_synth_list)
			var/material_path = GLOB.material_synth_list[tool]
			if(!target().can_install_synth(material_path)) //Don't add it to the list if we already have it!
				continue
			tools += list(list("name" = tool, "path" = material_path))
	else
		for(var/obj/tool in contents_of(mult_belt))
			integrated_tools += list(list("name" = tool.name, "ref" = "\ref[tool]"))
		for(var/tool in GLOB.all_borg_multitool_options)
			if(tool in mult_belt.cyborg_integrated_tools) //Don't add it to the list if we already have it!
				continue
			var/obj/item/tool_to_add = tool
			tools += list(list("name" = initial(tool_to_add.name), "path" = tool_to_add))
	multi_belt_list["integrated_tools"] = integrated_tools
	multi_belt_list["tools"] = tools
	return multi_belt_list

/datum/eventkit/modify_robot/proc/get_cells()
	var/list/cell_options = list()
	for(var/cell in typesof(/obj/item/cell))
		var/obj/item/cell/C = cell
		if(initial(C.name) == "power cell")
			continue
		if(ispath(C, /obj/item/cell/standin))
			continue
		if(ispath(C, /obj/item/cell/device))
			continue
		if(ispath(C, /obj/item/cell/mech))
			continue
		if(cell_options[initial(C.name)]) // empty cells are defined after normal cells!
			continue
		cell_options += list(initial(C.name) = list("path" = "[C]", "charge" = initial(C.maxcharge), "max_charge" = initial(C.maxcharge), "charge_amount" = initial(C.charge_amount) , "self_charge" = initial(C.self_recharge), "max_damage" = initial(C.robot_durability))) // our cells do not have their charge predefined, they do it on init, so both maaxcharge for now
	return cell_options

/datum/eventkit/modify_robot/proc/get_component(type)
	var/path
	switch(type)
		if("camera")
			path = /obj/item/robot_parts/robot_component/camera
		if("radio")
			path = /obj/item/robot_parts/robot_component/radio
		if("actuator")
			path = /obj/item/robot_parts/robot_component/actuator
		if("diagnosis")
			path = /obj/item/robot_parts/robot_component/diagnosis_unit
		if("comms")
			path = /obj/item/robot_parts/robot_component/binary_communication_device
		if("armour")
			path = /obj/item/robot_parts/robot_component/armour
	if(!path)
		return
	var/list/components = list()
	for(var/component in typesof(path))
		var/obj/item/robot_parts/robot_component/C = component
		components += list("[initial(C.name)]" = list("path" = "[component]", "idle_usage" = "[C.idle_usage]", "active_usage" = "[C.active_usage]", "max_damage" = "[C.max_damage]"))
	return components

/datum/eventkit/modify_robot/proc/get_gear()
	var/list/equip = list()
	for(var/datum/robot_component/C as anything in target().components)
		if(C.internal || C.slot == ROBOT_SLOT_POWER)
			continue
		var/component_name
		if(istype(C.wrapped, /obj/item/robot_parts/robot_component))
			component_name = C.wrapped.name
		equip += list("[lowertext(C.name)]" = "[component_name]")
	return equip

/datum/eventkit/modify_robot/proc/get_components()
	var/list/components = list()
	for(var/datum/robot_component/C as anything in target().components)
		components += list(list("name" = C.name, "ref" = "\ref[C]", "brute_damage" = C.get_structural_damage(), "electronics_damage" = C.get_wiring_damage(), "max_damage" = C.max_damage, "idle_usage" = C.idle_usage, "active_usage" = C.active_usage, "installed" = C.installed, "exists" = (C.wrapped ? TRUE : FALSE)))
	return components

/datum/eventkit/modify_robot/proc/package_laws(list/data, field, list/datum/ai_law/laws)
	var/list/packaged_laws = list()
	for(var/datum/ai_law/AL in laws)
		packaged_laws[++packaged_laws.len] = list("law" = AL.law, "index" = AL.get_index(), "state" = target().laws.get_state_law(AL), "ref" = "\ref[AL]")
	data[field] = packaged_laws
	data["has_[field]"] = packaged_laws.len

/datum/eventkit/modify_robot/proc/package_multiple_laws(list/datum/ai_laws/laws)
	var/list/law_sets = list()
	for(var/datum/ai_laws/ALs in laws)
		var/list/packaged_laws = list()
		package_laws(packaged_laws, "zeroth_laws", list(ALs.zeroth_law, ALs.zeroth_law_borg))
		package_laws(packaged_laws, "ion_laws", ALs.ion_laws)
		package_laws(packaged_laws, "inherent_laws", ALs.inherent_laws)
		package_laws(packaged_laws, "supplied_laws", ALs.supplied_laws)
		law_sets[++law_sets.len] = list("name" = ALs.name, "header" = ALs.law_header, "ref" = "\ref[ALs]","laws" = packaged_laws)
	return law_sets

/datum/eventkit/modify_robot/proc/is_malf(mob/user)
	return (is_admin(user) && !target().is_slaved()) || is_special_role(user)

/datum/eventkit/modify_robot/proc/is_special_role(mob/user)
	return user.mind?.special_role ? TRUE : FALSE

/// LC-refs: Currently selected multibelt. -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/eventkit/modify_robot/proc/multibelt_holder() as /obj/item/robotic_multibelt
	return om_resolve(multibelt_holder_handle)

/// LC-refs: the target this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/eventkit/modify_robot/proc/target() as /mob/living/silicon/robot
	return om_resolve(target_handle)

DECLARE_REF(/datum/eventkit/modify_robot, "law_list", OWNED_LIST, null)
