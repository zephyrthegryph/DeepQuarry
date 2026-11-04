//PKA
/obj/item/borg/upgrade/restricted/pka
	name = "Protokenetic Accelerator Upgrade"
	desc = "A borg mounted PKA Rifle for use in mining and wildlife defense."
	icon_state = "cyborg_upgrade3"
	item_state = "cyborg_upgrade"
	module_flags = BORG_MODULE_MINER
	require_module = TRUE

/obj/item/borg/upgrade/restricted/pka/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(!R.supports_upgrade(type))
		generic_error(user, R, type)
		return FALSE

	if(is_installed(R))
		generic_error(user, R, type)
		return FALSE

	R.module.modules += new/obj/item/gun/energy/kinetic_accelerator/cyborg(R.module)
	return TRUE
