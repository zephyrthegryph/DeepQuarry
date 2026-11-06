/obj/item/borg/upgrade/advanced/bellysizeupgrade
	name = "robohound capacity expansion module"
	desc = "Used to double a robohound's belly capacity. This only affects total volume, and won't allow support of more than one patient in case of sleeper bellies. Can only be applied once."
	icon_state = "cyborg_upgrade2"
	item_state = "cyborg_upgrade"
	require_module = TRUE

/obj/item/borg/upgrade/advanced/bellysizeupgrade/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	var/obj/T = R.has_upgrade_module(/obj/item/dogborg/sleeper)
	if(!T)
		to_chat(user, span_warning("This robot has had its processor removed!"))
		return FALSE

	if(is_installed(R))
		to_chat(R, span_warning("Maximum capacity achieved for this hardpoint!"))
		to_chat(user, span_warning("There's no room for another capacity upgrade!"))
		return FALSE

	var/obj/item/dogborg/sleeper/B = T
	var/X = B.max_item_count*2
	B.set_max_item_count(X)	//I couldn't do T = maxitem*2 for some reason.
	to_chat(R, span_notice("Internal capacity doubled."))
	to_chat(user, span_notice("Internal capacity doubled."))
	B.upgraded_capacity = TRUE
	return TRUE
