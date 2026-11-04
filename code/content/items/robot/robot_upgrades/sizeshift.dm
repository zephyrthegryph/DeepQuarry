/obj/item/borg/upgrade/basic/sizeshift
	name = "robot size alteration module"
	desc = "Using technology similar to one used in sizeguns, allows cyborgs to adjust their own size as neccesary."
	icon_state = "cyborg_upgrade2"
	item_state = "cyborg_upgrade"
	require_module = TRUE

/obj/item/borg/upgrade/basic/sizeshift/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(is_installed(R))
		to_chat(R, span_warning("Size alteration module already applied!"))
		to_chat(user, span_warning("There's no space for another size alteration module!"))
		return FALSE

	grant(R, granted_verb(/mob/living/proc/set_size), R)
	to_chat(R, span_notice("Size adjustments active!"))
	return TRUE
