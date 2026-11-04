//Diamond Drill
/obj/item/borg/upgrade/restricted/diamonddrill
	name = "Mounted Diamond Drill"
	desc = "An advanced drill, optimized for borg use."
	icon_state = "cyborg_upgrade3"
	item_state = "cyborg_upgrade"
	module_flags = BORG_MODULE_MINER
	require_module = TRUE

/obj/item/borg/upgrade/restricted/diamonddrill/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(!R.supports_upgrade(type))
		generic_error(user, R, type)
		return FALSE

	if(is_installed(R))
		generic_error(user, R, type)
		return FALSE

	R.module.modules += new/obj/item/pickaxe/diamonddrill(R.module)
	return TRUE
