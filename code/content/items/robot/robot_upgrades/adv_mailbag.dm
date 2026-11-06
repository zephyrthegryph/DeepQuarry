/obj/item/borg/upgrade/restricted/adv_mailbag
	name = "robotic mailbag capacity module"
	desc = "Used to expand the mailbag storage."
	icon_state = "cyborg_upgrade3"
	item_state = "cyborg_upgrade"
	module_flags = BORG_MODULE_MINER
	require_module = TRUE

/obj/item/borg/upgrade/restricted/adv_mailbag/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(!R.supports_upgrade(type))
		generic_error(user, R, type)
		return FALSE

	var/obj/target_module = R.has_upgrade_module(/obj/item/storage/bag/mail/borg)
	if(!target_module)
		to_chat(user, span_warning("This robot has had its letter compartment removed!"))
		return FALSE

	if(is_installed(R))
		to_chat(R, span_warning("Letter compartment was already upgraded!"))
		to_chat(user, span_warning("There's no room for another letter compartment upgrade!"))
		return FALSE

	var/obj/item/storage/bag/mail/borg/mailbag = target_module
	mailbag.upgrade()
	to_chat(R, span_notice("Letter compartment upgraded!"))
	return TRUE
