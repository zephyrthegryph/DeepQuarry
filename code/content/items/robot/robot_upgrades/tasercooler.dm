/obj/item/borg/upgrade/restricted/tasercooler
	name = "robotic Rapid Taser Cooling Module"
	desc = "Used to cool a mounted taser, increasing the potential current in it and thus its recharge rate."
	icon_state = "cyborg_upgrade3"
	item_state = "cyborg_upgrade"
	module_flags = BORG_MODULE_SECURITY
	require_module = TRUE

/obj/item/borg/upgrade/restricted/tasercooler/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(!R.supports_upgrade(type))
		generic_error(user, R, type)
		return FALSE

	var/obj/T = R.has_upgrade_module(/obj/item/gun/energy/robotic/taser)
	if(!T)
		to_chat(user, span_warning("This robot has had its taser removed!"))
		return FALSE

	if(is_installed(R))
		to_chat(R, span_warning("Maximum cooling achieved for this hardpoint!"))
		to_chat(user, span_warning("There's no room for another cooling unit!"))
		return FALSE

	var/obj/item/gun/energy/robotic/taser/B = T
	B.recharge_time = max(2 , B.recharge_time - 4)
	to_chat(R, span_notice("Taser cooling upgraded!"))
	return TRUE
