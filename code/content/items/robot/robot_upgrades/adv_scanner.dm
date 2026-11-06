/obj/item/borg/upgrade/restricted/adv_scanner
	name = "robotic Ore Scanning Upgrade Module"
	desc = "Used to improve the integrated robot scanning module, allowing for larger more fine-tuned scan ranges."
	icon_state = "cyborg_upgrade3"
	item_state = "cyborg_upgrade"
	module_flags = BORG_MODULE_MINER
	require_module = TRUE

/obj/item/borg/upgrade/restricted/adv_scanner/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(!R.supports_upgrade(type))
		generic_error(user, R, type)
		return FALSE

	var/obj/target_module = R.has_upgrade_module(/obj/item/mining_scanner/robot)
	if(!target_module)
		to_chat(user, span_warning("This robot has had its scanner removed!"))
		return FALSE

	if(is_installed(R))
		to_chat(R, span_warning("Scanner was already upgraded!"))
		to_chat(user, span_warning("There's no room for another scanning upgrade!"))
		return FALSE

	var/obj/item/mining_scanner/robot/robot_scanner = target_module
	robot_scanner.upgrade()
	to_chat(R, span_notice("Mining scanner upgraded!"))
	return TRUE
