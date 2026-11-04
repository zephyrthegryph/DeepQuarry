/obj/item/borg/upgrade/no_prod/vision_thermal
	name = "Robot thermal vision module"
	desc = "Vision alterantion software to add thermal sight capabilities."
	icon_state = "cyborg_upgrade5"
	item_state = "cyborg_upgrade"
	require_module = TRUE
	hidden_from_scan = TRUE

/obj/item/borg/upgrade/no_prod/vision_thermal/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(is_installed(R))
		software_error(user, R, type)
		return FALSE

	R.module.modules += new/obj/item/borg/sight/thermal(R.module)
	return TRUE
