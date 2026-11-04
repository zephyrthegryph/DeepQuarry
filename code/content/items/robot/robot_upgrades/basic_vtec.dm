/obj/item/borg/upgrade/basic/vtec
	name = "robotic VTEC Module"
	desc = "Used to kick in a robot's VTEC systems, increasing their speed."
	icon_state = "cyborg_upgrade2"
	item_state = "cyborg_upgrade"
	require_module = TRUE

/obj/item/borg/upgrade/basic/vtec/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(is_installed(R))
		to_chat(R,span_warning("Actuator already running on overdrive mode!"))
		to_chat(user, span_warning("It'd be unwise to plug another vtec module in!"))
		return FALSE

	grant(R, robot_vtec(), R)
	R.vtec_active = TRUE
	R.hud_used.toggle_vtec_control()
	to_chat(R, span_notice("Actuator overdrive enabled!"))
	return TRUE

/obj/item/borg/upgrade/basic/vtec/remove_upgrade(mob/living/silicon/robot/R)
	if(!is_installed(R))
		return
	revoke(R, robot_vtec(), R)
	R.vtec_active = FALSE
	if(R.hud_used)
		R.hud_used.toggle_vtec_control()
