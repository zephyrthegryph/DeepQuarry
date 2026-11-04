//Robot size gun
/obj/item/borg/upgrade/advanced/sizegun
	name = "robot mounted size gun"
	desc = "A size gun adapted for installation in cyborgs, allows them to turn people pocket-sized among other uses. What could go wrong?"
	icon_state = "cyborg_upgrade2"
	item_state = "cyborg_upgrade"
	require_module = TRUE

/obj/item/borg/upgrade/advanced/sizegun/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(is_installed(R))
		generic_error(user, R, type)
		return FALSE

	R.module.modules += new/obj/item/gun/energy/sizegun/mounted(R.module)
	return TRUE
