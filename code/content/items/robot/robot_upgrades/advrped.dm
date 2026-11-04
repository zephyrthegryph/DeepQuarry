//Advanced RPED
/obj/item/borg/upgrade/restricted/advrped
	name = "Advanced Rapid Part Exchange Device"
	desc = "An ARPED, now in borg size!"
	icon_state = "cyborg_upgrade3"
	item_state = "cyborg_upgrade"
	module_flags = BORG_MODULE_SCIENCE
	require_module = TRUE

/obj/item/borg/upgrade/restricted/advrped/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(!R.supports_upgrade(type))
		generic_error(user, R, type)
		return FALSE

	if(is_installed(R))
		generic_error(user, R, type)
		return FALSE

	R.module.modules += new/obj/item/storage/part_replacer/adv(R.module)
	return TRUE
