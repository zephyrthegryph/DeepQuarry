/*	##############################################################################
	# Restricted section. All upgrades which only work on specific modules go here.#
	##############################################################################*/

//adds the capability to ingest items to the sleeper modules as optional upgrade
/obj/item/borg/upgrade/restricted/bellycapupgrade
	name = "robohound capability expansion module"
	desc = "Used to enable a robohound's sleeper to ingest items. This only affects sleepers, and has no effect on compactor bellies. Can only be applied once."
	icon_state = "cyborg_upgrade2"
	item_state = "cyborg_upgrade"
	require_module = TRUE
	module_flags = BORG_MODULE_SECURITY | BORG_MODULE_MEDICAL | BORG_MODULE_COMBAT

/obj/item/borg/upgrade/restricted/bellycapupgrade/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(!R.supports_upgrade(type))
		generic_error(user, R, type)
		return FALSE

	var/obj/T = R.has_upgrade_module(/obj/item/dogborg/sleeper)
	if(!T)
		to_chat(user, span_warning("This robot has had its processor removed!"))
		return FALSE

	if(is_installed(R))
		to_chat(R, span_warning("Maximum capability achieved for this hardpoint!"))
		to_chat(user, span_warning("There's no room for another capability upgrade!"))
		return FALSE

	var/obj/item/dogborg/sleeper/B = T
	var/X = B.max_item_count*2 //double the capacity from 1 to 2 to allow sleepers to store some items, at most 4 with both upgrades
	B.set_max_item_count(X)	//I couldn't do T = maxitem*2 for some reason.
	to_chat(R, span_notice("Internal capability upgraded."))
	to_chat(user, span_notice("Internal capability upgraded."))
	B.set_compactor(TRUE)
	return TRUE
