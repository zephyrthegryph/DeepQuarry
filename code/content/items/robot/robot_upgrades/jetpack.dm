/obj/item/borg/upgrade/advanced/jetpack
	name = "robot jetpack"
	desc = "A carbon dioxide jetpack suitable for low-gravity operations."
	icon_state = "cyborg_upgrade3"
	item_state = "cyborg_upgrade"
	require_module = TRUE

/obj/item/borg/upgrade/advanced/jetpack/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(is_installed(R))
		generic_error(user, R, type)
		return FALSE

	rel_add(R.module, nameof(/obj/item/robot_module::modules), new /obj/item/tank/jetpack/carbondioxide(R.module))
	return TRUE
