ADMIN_VERB_AND_CONTEXT_MENU(modify_robot, R_ADMIN|R_FUN|R_VAREDIT|R_EVENT, "Modify Robot", "Allows to add or remove modules to/from robots.", ADMIN_CATEGORY_SILICON, mob/living/silicon/robot/target in REGISTRY_MEMBERS(REGISTRY_SILICONS))
	if(!target)
		return
	var/datum/eventkit/modify_robot/modify_robot = new()
	rel_set(modify_robot, nameof(/datum/eventkit/modify_robot::target), target)
	modify_robot.selected_ai = target.is_slaved()
	modify_robot.tgui_interact(user.mob)

/datum/eventkit/modify_robot
	var/tmp/mob/living/silicon/robot/target
	var/mob/living/silicon/robot/source
	var/selected_ai
	var/ion_law	= "IonLaw"
	var/zeroth_law = "ZerothLaw"
	var/inherent_law = "InherentLaw"
	var/supplied_law = "SuppliedLaw"
	var/supplied_law_position = MIN_SUPPLIED_LAW_NUMBER
	var/list/datum/ai_laws/law_list
	var/tmp/obj/item/robotic_multibelt/multibelt_holder	//Currently selected multibelt.
	/// The upgrade a question is open for.
	var/pending_upgrade
	/// The law a question about editing is open for (a view: the robot's laws own themselves).
	var/tmp/datum/ai_law/editing_law

CAPABILITIES(/datum/eventkit/modify_robot)
	op("add_zeroth_law", ui_act(), then(PROC_REF(ui_act_add_zeroth_law)))
	op("add_ion_law", ui_act(), then(PROC_REF(ui_act_add_ion_law)))
	op("add_inherent_law", ui_act(), then(PROC_REF(ui_act_add_inherent_law)))
	op("add_supplied_law", ui_act(), then(PROC_REF(ui_act_add_supplied_law)))
	op("toggle_crisis", ui_act(), then(PROC_REF(ui_act_toggle_crisis)))
	op("reset_module", ui_act(), then(PROC_REF(ui_act_reset_module)))
	op("ert_toggle", ui_act(), then(PROC_REF(ui_act_ert_toggle)))
	op("add_centcom", ui_act(), then(PROC_REF(ui_act_add_centcom)))
	op("rem_centcom", ui_act(), then(PROC_REF(ui_act_rem_centcom)))
	op("add_station", ui_act(), then(PROC_REF(ui_act_add_station)))
	op("rem_station", ui_act(), then(PROC_REF(ui_act_rem_station)))
	op("state_laws", ui_act(), then(PROC_REF(ui_act_state_laws)))
	op("disconnect_ai", ui_act(), then(PROC_REF(ui_act_disconnect_ai)))
	op("toggle_emag", ui_act(), then(PROC_REF(ui_act_toggle_emag)))
	owns_many(nameof(law_list), /datum/ai_laws)
	owns_one(nameof(source), /mob/living/silicon/robot)
	ref_one(nameof(editing_law), /datum/ai_law)
	interface("ModifyRobot", title = "Modify Robot", rights = R_ADMIN|R_EVENT|R_DEBUG)

	section(modules, "The Modify Robot panel's name, target, module, upgrades, modkits and tools")
	op("rename", ui_act("rename", arg("new_name", schema_text(4096))), then(PROC_REF(ui_act_rename)))
	op("select_target", ui_act("select_target", arg("new_target", schema_ref(null))), then(PROC_REF(ui_act_select_target)))
	op("toggle_crisis", ui_act("toggle_crisis"), then(PROC_REF(ui_act_toggle_crisis)))
	op("add_restriction", ui_act("add_restriction", arg("new_restriction", schema_text(4096))), then(PROC_REF(ui_act_add_restriction)))
	op("remove_restriction", ui_act("remove_restriction", arg("rem_restriction", schema_text(4096))), then(PROC_REF(ui_act_remove_restriction)))
	op("select_source", ui_act("select_source", arg("new_source")), then(PROC_REF(ui_act_select_source)))
	op("reset_module", ui_act("reset_module"), then(PROC_REF(ui_act_reset_module)))
	op("add_module", ui_act("add_module", arg("module", schema_ref(/obj/item))), then(PROC_REF(ui_act_add_module)))
	op("rem_module", ui_act("rem_module", arg("module", schema_ref(/obj/item))), then(PROC_REF(ui_act_rem_module)))
	op("swap_module", ui_act("swap_module"), then(PROC_REF(ui_act_swap_module)))
	op("ert_toggle", ui_act("ert_toggle"), then(PROC_REF(ui_act_ert_toggle)))
	op("add_compatibility", ui_act("add_compatibility", arg("upgrade", schema_path(/datum))), then(PROC_REF(ui_act_add_compatibility)))
	op("rem_compatibility", ui_act("rem_compatibility", arg("upgrade", schema_path(/datum))), then(PROC_REF(ui_act_rem_compatibility)))
	op("add_upgrade", ui_act("add_upgrade", arg("upgrade", schema_path(/datum))), then(PROC_REF(ui_act_add_upgrade)))
	op("install_modkit", ui_act("install_modkit", arg("modkit", schema_path(/datum))), then(PROC_REF(ui_act_install_modkit)))
	op("remove_modkit", ui_act("remove_modkit", arg("modkit", schema_ref(/obj/item))), then(PROC_REF(ui_act_remove_modkit)))
	op("select_multibelt", ui_act("select_multibelt", arg("multibelt", schema_ref(null))), then(PROC_REF(ui_act_select_multibelt)))
	op("install_tool", ui_act("install_tool", arg("tool", schema_path(/datum))), then(PROC_REF(ui_act_install_tool)))
	op("remove_tool", ui_act("remove_tool", arg("tool", schema_ref(/datum/matter_synth))), then(PROC_REF(ui_act_remove_tool)))

	section(parts, "The Modify Robot panel's radio channels, components, cell, damage and access")
	op("add_channel", ui_act("add_channel", arg("channel", schema_text(4096))), then(PROC_REF(ui_act_add_channel)))
	op("rem_channel", ui_act("rem_channel", arg("channel")), then(PROC_REF(ui_act_rem_channel)))
	op("add_component", ui_act("add_component", arg("component"), arg("new_part", schema_path(/datum))), then(PROC_REF(ui_act_add_component)))
	op("rem_component", ui_act("rem_component", arg("component")), then(PROC_REF(ui_act_rem_component)))
	op("adjust_cell_charge", ui_act("adjust_cell_charge", arg("charge", num())), then(PROC_REF(ui_act_adjust_cell_charge)))
	op("adjust_brute", ui_act("adjust_brute", arg("component"), arg("damage", num())), then(PROC_REF(ui_act_adjust_brute)))
	op("adjust_electronics", ui_act("adjust_electronics", arg("component"), arg("damage", num())), then(PROC_REF(ui_act_adjust_electronics)))
	op("add_access", ui_act("add_access", arg("access", num())), then(PROC_REF(ui_act_add_access)))
	op("rem_access", ui_act("rem_access", arg("access", num())), then(PROC_REF(ui_act_rem_access)))
	op("add_centcom", ui_act("add_centcom"), then(PROC_REF(ui_act_add_centcom)))
	op("rem_centcom", ui_act("rem_centcom"), then(PROC_REF(ui_act_rem_centcom)))
	op("add_station", ui_act("add_station"), then(PROC_REF(ui_act_add_station)))
	op("rem_station", ui_act("rem_station"), then(PROC_REF(ui_act_rem_station)))

	section(laws, "The Modify Robot panel's laws and AI link")
	op("law_channel", ui_act("law_channel", arg("law_channel", schema_text(4096))), then(PROC_REF(ui_act_law_channel)))
	op("state_law", ui_act("state_law", arg("ref"), arg("state_law", num())), then(PROC_REF(ui_act_state_law)))
	op("add_zeroth_law", ui_act("add_zeroth_law"), then(PROC_REF(ui_act_add_zeroth_law)))
	op("add_ion_law", ui_act("add_ion_law"), then(PROC_REF(ui_act_add_ion_law)))
	op("add_inherent_law", ui_act("add_inherent_law"), then(PROC_REF(ui_act_add_inherent_law)))
	op("add_supplied_law", ui_act("add_supplied_law"), then(PROC_REF(ui_act_add_supplied_law)))
	op("change_zeroth_law", ui_act("change_zeroth_law", arg("val", schema_text(4096))), then(PROC_REF(ui_act_change_zeroth_law)))
	op("change_ion_law", ui_act("change_ion_law", arg("val", schema_text(4096))), then(PROC_REF(ui_act_change_ion_law)))
	op("change_inherent_law", ui_act("change_inherent_law", arg("val", schema_text(4096))), then(PROC_REF(ui_act_change_inherent_law)))
	op("change_supplied_law", ui_act("change_supplied_law", arg("val", schema_text(4096))), then(PROC_REF(ui_act_change_supplied_law)))
	op("change_supplied_law_position", ui_act("change_supplied_law_position"), asks(/datum/prompt/number, fields = list("title" = "Law Position", "question" = "Enter new supplied law position between 1 and [MAX_SUPPLIED_LAW_NUMBER], inclusive. Inherent laws at the same index as a supplied law will not be stated.", "default" = computed(PROC_REF(law_position_default)), "max_value" = MAX_SUPPLIED_LAW_NUMBER, "min_value" = 1)), then(PROC_REF(ui_act_change_supplied_law_position)))
	op("edit_law", ui_act("edit_law", arg("edit_law")), then(PROC_REF(ui_act_edit_law)))
	op("delete_law", ui_act("delete_law", arg("delete_law")), then(PROC_REF(ui_act_delete_law)))
	op("state_laws", ui_act("state_laws"), then(PROC_REF(ui_act_state_laws)))
	op("state_law_set", ui_act("state_law_set", arg("state_law_set", schema_ref(/datum/ai_laws))), then(PROC_REF(ui_act_state_law_set)))
	op("transfer_laws", ui_act("transfer_laws", arg("transfer_laws", schema_ref(/datum/ai_laws))), then(PROC_REF(ui_act_transfer_laws)))
	op("notify_laws", ui_act("notify_laws"), then(PROC_REF(ui_act_notify_laws)))
	op("select_ai", ui_act("select_ai", arg("new_ai")), then(PROC_REF(ui_act_select_ai)))
	op("swap_sync", ui_act("swap_sync"), then(PROC_REF(ui_act_swap_sync)))
	op("disconnect_ai", ui_act("disconnect_ai"), then(PROC_REF(ui_act_disconnect_ai)))
	op("toggle_emag", ui_act("toggle_emag"), then(PROC_REF(ui_act_toggle_emag)))

/datum/eventkit/modify_robot/New()
	. = ..()
	log_and_message_admins("has used modify robot and is modifying [target()]")
	var/list/laws = list()
	init_subtypes(/datum/ai_laws, laws)
	for(var/datum/ai_laws/laws_entry as anything in dd_sortedObjectList(laws))
		rel_add(src, nameof(law_list), laws_entry)

/datum/eventkit/modify_robot/tgui_close()
	rel_clear(src, nameof(target))
	if(source)
		rel_clear(src, nameof(source))

/datum/eventkit/modify_robot/ui_assets(mob/user)
	if(!target())
		return list()
	var/datum/asset/spritesheet_batched/robot_icons/spritesheet = GLOB.robot_sprite_sheets[target().modtype]
	return spritesheet ? list(spritesheet) : list()

/datum/eventkit/modify_robot/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	. = list()
	.["ion_law"] = ion_law
	.["zeroth_law"] = zeroth_law
	.["inherent_law"] = inherent_law
	.["supplied_law"] = supplied_law
	.["supplied_law_position"] = supplied_law_position
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

/datum/eventkit/modify_robot/proc/ui_act_rename(datum/act/op/A, new_name)
	target().name = new_name
	target().custom_name = new_name
	target().real_name = new_name
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_select_target(datum/act/op/A, new_target_arg)
	var/new_target = new_target_arg
	if(new_target != target())
		rel_set(src, nameof(/datum/eventkit/modify_robot::target), new_target_arg)
		log_and_message_admins("changed robot modifictation target to [target()]")
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_toggle_crisis(datum/act/op/A)
	target().crisis_override = !target().crisis_override
	return OP_OK

/datum/eventkit/modify_robot/proc/ui_act_add_restriction(datum/act/op/A, new_restriction_arg)
	var/new_restriction = new_restriction_arg
	if(!(new_restriction in GLOB.robot_modules))
		return FALSE
	var/mob/living/silicon/robot/robot_target = target()
	LAZYOR(robot_target.restrict_modules_to, new_restriction)
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_remove_restriction(datum/act/op/A, rem_restriction_arg)
	var/rem_restriction = rem_restriction_arg
	if(!(rem_restriction in GLOB.robot_modules))
		return FALSE
	var/mob/living/silicon/robot/robot_target = target()
	LAZYREMOVE(robot_target.restrict_modules_to, rem_restriction)
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_select_source(datum/act/op/A, new_source)
	if(source)
		rel_clear(src, nameof(source))
	var/module_type = GLOB.robot_modules[new_source]
	if(ispath(module_type, /obj/item/robot_module/robot/syndicate))
		rel_set(src, nameof(source), new /mob/living/silicon/robot/syndicate(null))
	else if(ispath(module_type, /obj/item/robot_module/robot/malf))
		rel_set(src, nameof(source), new /mob/living/silicon/robot/malf(null))
	else
		rel_set(src, nameof(source), new /mob/living/silicon/robot(null))
	source.modtype = new_source
	var/obj/item/robot_module/robot/robot_type = new module_type(source)
	proto_set(source, nameof(/datum/tgui_module/robot_ui_module::sprite_datum), pick(SSrobot_sprites.get_module_sprites(source.modtype, source)))
	source.update_icon()
	source.emag_items = TRUE
	if(!istype(robot_type, /obj/item/robot_module/robot))
		rel_clear(src, nameof(/datum/eventkit/modify_robot::source))
		return TRUE
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_reset_module(datum/act/op/A)
	target().module_reset(FALSE)
	return OP_OK

/datum/eventkit/modify_robot/proc/ui_act_add_module(datum/act/op/A, module)
	var/obj/item/selected_item = module
	if(!selected_item)
		return TRUE
	if(istype(selected_item, /obj/item/card/id))
		rel_take(source, nameof(/mob/living/silicon::idcard))
	source.module.emag -= selected_item
	source.module.modules -= selected_item
	target().module.add_item(selected_item, target())
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_rem_module(datum/act/op/A, module)
	var/obj/item/rem_item = module
	if(target().idcard == rem_item)
		target().idcard = new /obj/item/card/id/synthetic(target())
	target().uneq_all()
	target().hud_used?.update_robot_modules_display(TRUE)
	target().module.emag.Remove(rem_item)
	target().module.modules.Remove(rem_item)
	rem_item.moveToNullspace()
	target().hud_used?.update_robot_modules_display()
	spent(rem_item)
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_swap_module(datum/act/op/A)
	if(!source)
		return FALSE
	var/mod_type = source.modtype
	rel_clear(source, nameof(/mob/living/silicon/robot::module))
	var/module_type = GLOB.robot_modules[target().modtype]
	source.modtype = target().modtype
	new module_type(source)
	// The target's sprite is shared (a registered sprite) or its private copy: copy a private one.
	var/datum/robot_sprite/target_sprite = target().sprite_datum
	proto_set(source, nameof(/datum/tgui_module/robot_ui_module::sprite_datum), (!target_sprite || is_registered(target_sprite)) ? target_sprite : target_sprite.proto_copy())
	source.update_icon()
	source.emag_items = TRUE
	// Target
	target().uneq_all()
	target().hud_used?.update_robot_modules_display(TRUE)
	rel_clear(target(), nameof(/mob/living/silicon/robot::module))
	target().modtype = mod_type
	module_type = GLOB.robot_modules[mod_type]
	target().transform_with_anim()
	new module_type(target())
	target().hands.icon_state = target().get_hud_module_icon()
	target().hud_used?.update_robot_modules_display()
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_ert_toggle(datum/act/op/A)
	target().crisis_override = !target().crisis_override
	target().module_reset(FALSE)
	return OP_OK

/datum/eventkit/modify_robot/proc/ui_act_add_compatibility(datum/act/op/A, upgrade)
	var/mob/living/silicon/robot/robot_target = target()
	LAZYOR(robot_target.module.supported_upgrades, upgrade)
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_rem_compatibility(datum/act/op/A, upgrade)
	var/mob/living/silicon/robot/robot_target = target()
	LAZYREMOVE(robot_target.module.supported_upgrades, upgrade)
	return TRUE

/// The answer to a question a button asked still counts (its window is still open and interactive for the one who answers).
/datum/eventkit/modify_robot/proc/request_usable(datum/request/R)
	return window_request_usable(src, R)

/datum/eventkit/modify_robot/proc/ui_act_add_upgrade(datum/act/op/A, upgrade_arg)
	var/mob/user = A.actor
	if(upgrade_arg == /obj/item/borg/upgrade/utility/reset)
		pending_upgrade = upgrade_arg
		var/obj/item/borg/upgrade/utility/reset/rmodul = upgrade_arg
		open_request(src, /datum/prompt/yes_no, PROC_REF(upgrade_reset_confirmed), valid = PROC_REF(request_usable), answerer = user, question = "Are you sure that you want to install [initial(rmodul.name)] and reset the robot's module?", title = "Confirm", timeout = 0)
		return TRUE
	if(upgrade_arg == /obj/item/borg/upgrade/utility/rename)
		pending_upgrade = upgrade_arg
		var/obj/item/borg/upgrade/utility/rename/renamer = upgrade_arg
		open_request(src, /datum/prompt/text, PROC_REF(upgrade_renamed), valid = PROC_REF(request_usable), answerer = user, question = "Enter new robot name", title = "Robot Reclassification", default = initial(renamer.heldname), max_len = MAX_NAME_LEN, name_text = TRUE, encode = FALSE, timeout = 0)
		return TRUE
	return install_upgrade(user, upgrade_arg, null)

/datum/eventkit/modify_robot/proc/upgrade_reset_confirmed(datum/act/request/A)
	if(!A.answer || !A.answer.value || !ispath(pending_upgrade))
		return
	install_upgrade(A.request.answerer, pending_upgrade, null)
	SStgui.update_uis(src)

/datum/eventkit/modify_robot/proc/upgrade_renamed(datum/act/request/A)
	if(!A.answer || isnull(A.answer.value) || !ispath(pending_upgrade))
		return
	install_upgrade(A.request.answerer, pending_upgrade, A.answer.value)
	SStgui.update_uis(src)

/// Builds the upgrade and installs it in the target.
/datum/eventkit/modify_robot/proc/install_upgrade(mob/user, new_upgrade, new_name)
	var/obj/item/borg/upgrade/U = new new_upgrade(null)
	if(new_upgrade == /obj/item/borg/upgrade/utility/rename)
		var/obj/item/borg/upgrade/utility/rename/UN = U
		new_name = sanitizeSafe(new_name, MAX_NAME_LEN)
		if(new_name)
			UN.heldname = new_name
		U = UN
	if(istype(U, /obj/item/borg/upgrade/restricted))
		var/mob/living/silicon/robot/robot_target = target()
		LAZYOR(robot_target.module.supported_upgrades, new_upgrade)
	if(!U.action(user, target()))
		return FALSE
	U.forceMove(target())
	target().hud_used?.update_robot_modules_display()
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_install_modkit(datum/act/op/A, modkit_arg)
	var/new_modkit = modkit_arg
	var/obj/item/gun/energy/kinetic_accelerator/kin = locate_in_list(target().module.modules, /obj/item/gun/energy/kinetic_accelerator)
	var/obj/item/borg/upgrade/modkit/M = new new_modkit(null)
	M.install(kin, target())
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_remove_modkit(datum/act/op/A, modkit)
	var/obj/item/gun/energy/kinetic_accelerator/kin = locate_in_list(target().module.modules, /obj/item/gun/energy/kinetic_accelerator)
	var/obj/item/rem_kit = modkit
	rel_remove(kin, nameof(/obj/item/gun/energy/kinetic_accelerator::modkits), rem_kit)
	spent(rem_kit)
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_select_multibelt(datum/act/op/A, multibelt)
	rel_set(src, nameof(/datum/eventkit/modify_robot::multibelt_holder), multibelt)
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_install_tool(datum/act/op/A, tool)
	if(!istype(multibelt_holder(), /obj/item/robotic_multibelt))
		return FALSE
	if(istype(multibelt_holder(), /obj/item/robotic_multibelt/materials))
		target().add_new_material(tool)
		return TRUE
	var/new_tool = tool
	if(new_tool in GLOB.all_borg_multitool_options)
		multibelt_holder().cyborg_integrated_tools += new_tool //Make sure you don't add items directly to it, or you can't ever remove them.
		multibelt_holder().generate_tools()
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_remove_tool(datum/act/op/A, tool)
	if(!istype(multibelt_holder(), /obj/item/robotic_multibelt))
		return FALSE
	if(istype(multibelt_holder(), /obj/item/robotic_multibelt/materials))
		var/datum/matter_synth/synth = tool
		target().module.synths -= synth
		spent(synth)
		target().update_material_multibelts()
		return TRUE
	var/obj/item/rem_tool = tool
	if(multibelt_holder().selected_item == rem_tool)
		multibelt_holder().dropped() //Reset to original icon.
	rem_tool.moveToNullspace()
	multibelt_holder().cyborg_integrated_tools -= rem_tool.type
	multibelt_holder().integrated_tools_by_name -= rem_tool.name
	multibelt_holder().integrated_tool_images -= rem_tool.name
	spent(rem_tool)
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_add_channel(datum/act/op/A, channel)
	var/selected_radio_channel = channel
	if(selected_radio_channel == CHANNEL_SPECIAL_OPS || selected_radio_channel == CHANNEL_RESPONSE_TEAM)
		target().radio.centComm = 1
	if(selected_radio_channel == CHANNEL_RAIDER)
		rel_clear(target().radio, nameof(/obj/item/radio/borg::keyslot), OWN_DELETE)
		target().radio.keyslot = new /obj/item/encryptionkey/raider(target())
		target().radio.syndie = 1
	if(selected_radio_channel == CHANNEL_MERCENARY)
		rel_clear(target().radio, nameof(/obj/item/radio/borg::keyslot), OWN_DELETE)
		target().radio.keyslot = new /obj/item/encryptionkey/syndicate(target())
		target().radio.syndie = 1
	target().module.channels += list("[selected_radio_channel]" = 1)
	target().radio.channels[selected_radio_channel] = LAZYACCESS(target().module.channels, selected_radio_channel)
	target().radio.secure_radio_connections[selected_radio_channel] = SSradio.add_object(target().radio, GLOB.radiochannels[selected_radio_channel],  RADIO_CHAT)
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_rem_channel(datum/act/op/A, channel)
	var/selected_radio_channel = channel
	if((selected_radio_channel == CHANNEL_SPECIAL_OPS || selected_radio_channel == CHANNEL_RESPONSE_TEAM) && !(LAZYACCESS(target().module.channels, CHANNEL_SPECIAL_OPS) || LAZYACCESS(target().module.channels, CHANNEL_RESPONSE_TEAM)))
		target().radio.centComm = 0
	if(target().module.channels)
		target().module.channels -= selected_radio_channel
	if((selected_radio_channel == CHANNEL_MERCENARY || selected_radio_channel == CHANNEL_RAIDER) && !(LAZYACCESS(target().module.channels, CHANNEL_RAIDER) || LAZYACCESS(target().module.channels, CHANNEL_MERCENARY)))
		rel_clear(target().radio, nameof(/obj/item/radio/borg::keyslot), OWN_DELETE)
		target().radio.keyslot = null
		target().radio.syndie = 0
	target().radio.channels = list()
	for(var/n_chan in target().module.channels)
		target().radio.channels[n_chan] = LAZYACCESS(target().module.channels, n_chan)
	SSradio.remove_object(target().radio, GLOB.radiochannels[selected_radio_channel])
	target().radio.secure_radio_connections -= selected_radio_channel
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_add_component(datum/act/op/A, component, new_part)
	var/datum/robot_component/C = ui_ref(component, ui_source_target_components(), /datum/robot_component)
	if(!C || C.internal)
		return FALSE
	var/new_component = new_part
	if(C.slot == ROBOT_SLOT_POWER)
		if(!ispath(new_component, /obj/item/cell))
			return FALSE
		spent(target().remove_cell())
		target().set_cell(new new_component(target()))
		return TRUE
	if(!ispath(new_component, C.external_type))
		new_component = C.external_type
	if(C.wrapped)
		spent(C.uninstall())
	C.clear_located_damage()
	C.install(new new_component(target()))
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_rem_component(datum/act/op/A, component)
	var/datum/robot_component/C = ui_ref(component, ui_source_target_components(), /datum/robot_component)
	if(!C?.wrapped || C.internal)
		return FALSE
	if(C.slot == ROBOT_SLOT_POWER)
		spent(target().remove_cell())
		return TRUE
	spent(C.uninstall())
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_adjust_cell_charge(datum/act/op/A, charge)
	var/obj/item/cell/cell = target().cell
	if(!cell)
		return FALSE
	var/delta = clamp(charge, 0, cell.maxcharge) - cell.charge
	if(delta > 0)
		target().add_power(ROBOT_CELL_JOULES(delta), src)
	else if(delta < 0)
		target().draw_power(ROBOT_CELL_JOULES(-delta), src, 0, TRUE)
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_adjust_brute(datum/act/op/A, component, damage)
	var/datum/robot_component/C = ui_ref(component, ui_source_target_components(), /datum/robot_component)
	if(!C)
		return FALSE
	C.set_located_damage(damage, C.get_wiring_damage())
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_adjust_electronics(datum/act/op/A, component, damage)
	var/datum/robot_component/C = ui_ref(component, ui_source_target_components(), /datum/robot_component)
	if(!C)
		return FALSE
	C.set_located_damage(C.get_structural_damage(), damage)
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_add_access(datum/act/op/A, access)
	target().idcard.access += access
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_rem_access(datum/act/op/A, access)
	target().idcard.access -= access
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_add_centcom(datum/act/op/A)
	target().idcard.access |= SSaccess.get_all_centcom_access()
	return OP_OK

/datum/eventkit/modify_robot/proc/ui_act_rem_centcom(datum/act/op/A)
	target().idcard.access -= SSaccess.get_all_centcom_access()
	return OP_OK

/datum/eventkit/modify_robot/proc/ui_act_add_station(datum/act/op/A)
	target().idcard.access |= SSaccess.get_all_station_access()
	target().idcard.access |= ACCESS_SYNTH
	return OP_OK

/datum/eventkit/modify_robot/proc/ui_act_rem_station(datum/act/op/A)
	target().idcard.access -= SSaccess.get_all_station_access()
	target().idcard.access -= ACCESS_SYNTH
	return OP_OK

/datum/eventkit/modify_robot/proc/ui_act_law_channel(datum/act/op/A, law_channel)
	if(law_channel in target().law_channels())
		target().lawchannel = law_channel
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_state_law(datum/act/op/A, ref, state_law_arg)
	var/datum/ai_law/AL = ui_ref(ref, ui_source_target_laws_all_laws(), /datum/ai_law)
	if(AL)
		var/state_law = state_law_arg
		target().laws.set_state_law(AL, state_law)
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_add_zeroth_law(datum/act/op/A)
	if(zeroth_law && !target().laws.zeroth_law)
		target().set_zeroth_law(zeroth_law)
		target().lawsync()
	return OP_OK

/datum/eventkit/modify_robot/proc/ui_act_add_ion_law(datum/act/op/A)
	if(ion_law)
		target().add_ion_law(ion_law)
		target().lawsync()
	return OP_OK

/datum/eventkit/modify_robot/proc/ui_act_add_inherent_law(datum/act/op/A)
	if(inherent_law)
		target().add_inherent_law(inherent_law)
		target().lawsync()
	return OP_OK

/datum/eventkit/modify_robot/proc/ui_act_add_supplied_law(datum/act/op/A)
	if(supplied_law && supplied_law_position >= 1 && MIN_SUPPLIED_LAW_NUMBER <= MAX_SUPPLIED_LAW_NUMBER)
		target().add_supplied_law(supplied_law_position, supplied_law)
		target().lawsync()
	return OP_OK

/datum/eventkit/modify_robot/proc/ui_act_change_zeroth_law(datum/act/op/A, val)
	var/new_law = sanitize(val)
	if(new_law && new_law != zeroth_law)
		zeroth_law = new_law
		target().lawsync()
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_change_ion_law(datum/act/op/A, val)
	var/new_law = sanitize(val)
	if(new_law && new_law != ion_law)
		ion_law = new_law
		target().lawsync()
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_change_inherent_law(datum/act/op/A, val)
	var/new_law = sanitize(val)
	if(new_law && new_law != inherent_law)
		inherent_law = new_law
		target().lawsync()
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_change_supplied_law(datum/act/op/A, val)
	var/new_law = sanitize(val)
	if(new_law && new_law != supplied_law)
		supplied_law = new_law
		target().lawsync()
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_change_supplied_law_position(datum/act/op/A)
	var/datum/prompt/P = A.answer
	var/new_position = P?.value
	if(isnum(new_position))
		supplied_law_position = CLAMP(new_position, 1, MAX_SUPPLIED_LAW_NUMBER)
		target().lawsync()
	return TRUE

/datum/eventkit/modify_robot/proc/law_position_default(datum/act/op/A)
	return supplied_law_position

/datum/eventkit/modify_robot/proc/ui_act_edit_law(datum/act/op/A, edit_law)
	var/datum/ai_law/AL = ui_ref(edit_law, ui_source_target_laws_all_laws(), /datum/ai_law)
	if(!AL)
		return TRUE
	rel_set(src, nameof(editing_law), AL)
	open_request(src, /datum/prompt/text, PROC_REF(law_edited), valid = PROC_REF(request_usable), answerer = A.actor, question = "Enter new law. Leaving the field blank will cancel the edit.", title = "Edit Law", default = AL.law, timeout = 0)
	return TRUE

/datum/eventkit/modify_robot/proc/law_edited(datum/act/request/A)
	law_edited_apply(A)
	SStgui.update_uis(src)

/datum/eventkit/modify_robot/proc/law_edited_apply(datum/act/request/A)
	var/datum/ai_law/AL = editing_law()
	if(!A.answer || !AL || !(AL in ui_source_target_laws_all_laws()))
		return
	var/new_law = A.answer.value
	if(new_law && new_law != AL.law)
		AL.law = new_law
		target().lawsync()

/// The law a question about editing is open for.
/datum/eventkit/modify_robot/proc/editing_law() as /datum/ai_law
	return editing_law

/datum/eventkit/modify_robot/proc/ui_act_delete_law(datum/act/op/A, delete_law)
	var/datum/ai_law/AL = ui_ref(delete_law, ui_source_target_laws_all_laws(), /datum/ai_law)
	if(AL)
		target().delete_law(AL)
		target().lawsync()
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_state_laws(datum/act/op/A)
	target().statelaws(target().laws)
	return OP_OK

/datum/eventkit/modify_robot/proc/ui_act_state_law_set(datum/act/op/A, state_law_set)
	var/datum/ai_laws/ALs = state_law_set
	if(ALs)
		target().statelaws(ALs)
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_transfer_laws(datum/act/op/A, transfer_laws)
	var/datum/ai_laws/ALs = transfer_laws
	if(ALs)
		ALs.sync(target(), 0)
		target().lawsync()
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_notify_laws(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(target(), span_danger("Law Notice\n") + target().laws.get_formatted_laws())
	if(isAI(target()))
		var/mob/living/silicon/ai/our_ai = target()
		for(var/mob/living/silicon/robot/R in our_ai.connected_robots)
			to_chat(R, span_danger("Law Notice\n") + R.laws.get_formatted_laws())
	if(user != target())
		to_chat(user, span_notice("Laws displayed."))
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_select_ai(datum/act/op/A, new_ai)
	selected_ai = new_ai
	return TRUE

/datum/eventkit/modify_robot/proc/ui_act_swap_sync(datum/act/op/A)
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

/datum/eventkit/modify_robot/proc/ui_act_disconnect_ai(datum/act/op/A)
	if(target().is_slaved())
		target().disconnect_from_ai()
		target().lawupdate = FALSE
	return OP_OK

/datum/eventkit/modify_robot/proc/ui_act_toggle_emag(datum/act/op/A)
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
	return OP_OK

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

/// Currently selected multibelt. (a relation view: null once that is deleted).
/datum/eventkit/modify_robot/proc/multibelt_holder() as /obj/item/robotic_multibelt
	return multibelt_holder

/// The target this refers to (a relation view: null once that is deleted).
/datum/eventkit/modify_robot/proc/target() as /mob/living/silicon/robot
	return target
