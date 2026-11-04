/obj/item/borg/upgrade/restricted/adv_snatcher
	name = "robotic Sheet Capacity Module"
	desc = "Used to expand the robot sheet storage."
	icon_state = "cyborg_upgrade3"
	item_state = "cyborg_upgrade"
	module_flags = BORG_MODULE_MINER
	require_module = TRUE

/obj/item/borg/upgrade/restricted/adv_snatcher/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(!R.supports_upgrade(type))
		generic_error(user, R, type)
		return FALSE

	var/obj/target_module = R.has_upgrade_module(/obj/item/storage/bag/sheetsnatcher/borg)
	if(!target_module)
		to_chat(user, span_warning("This robot has had its sheet snatcher removed!"))
		return FALSE

	if(is_installed(R))
		to_chat(R, span_warning("Sheet capacity was already upgraded!"))
		to_chat(user, span_warning("There's no room for another sheet capacity upgrade!"))
		return FALSE

	var/obj/item/storage/bag/sheetsnatcher/borg/robot_snatcher = target_module
	robot_snatcher.upgrade()
	to_chat(R, span_notice("Sheet snatcher upgraded!"))
	return TRUE
