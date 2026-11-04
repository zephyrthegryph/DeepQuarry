/obj/item/borg/upgrade/basic/syndicate
	name = "scrambled equipment module"
	desc = "Unlocks new and often deadly module specific items of a robot"
	icon_state = "cyborg_upgrade3"
	item_state = "cyborg_upgrade"
	require_module = TRUE

/obj/item/borg/upgrade/basic/syndicate/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(is_installed(R))
		to_chat(R, span_warning("Secret modules already unlocked!"))
		to_chat(user, span_warning("Plugging another scambled module would be useless!"))
		return FALSE

	R.set_emag_items(TRUE)
	R.robotact.update_static_data_for_all_viewers()
	return TRUE
