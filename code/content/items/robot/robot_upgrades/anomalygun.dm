// Anomaly Gun
/obj/item/borg/upgrade/restricted/anomalygun
	name = "robot mounted particle gun"
	desc = "A anomaly particle gun adapted for installation in cyborgs, allows them to shoot different particles upon anomalies."
	icon_state = "cyborg_upgrade2"
	item_state = "cyborg_upgrade"
	module_flags = BORG_MODULE_SCIENCE
	require_module = TRUE

/obj/item/borg/upgrade/restricted/anomalygun/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(!R.supports_upgrade(type))
		generic_error(user, R, type)
		return FALSE

	if(is_installed(R))
		generic_error(user, R, type)
		return FALSE

	R.module.modules += new/obj/item/gun/energy/anomaly/mounted(R.module)
	return TRUE
