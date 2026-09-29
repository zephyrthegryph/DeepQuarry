/obj/item/pai_cable/proc/plugin(obj/machinery/M, mob/user)
	if(istype(M, /obj/machinery/door) || istype(M, /obj/machinery/camera))
		if(istype(M, /obj/machinery/door/airlock))
			var/obj/machinery/door/airlock/A = M
			if(A.secured_wires)
				to_chat(user,span_warning("\The [M] doesn't have any acessible data ports for \the [src]!"))
				return
		act_message(user, src, MSG_SELF("You insert %T% into a data port on [M]."), MSG_OTHERS("%U% inserts %T% into a data port on [M]."), MSG_BLIND("You hear the satisfying click of a wire jack fastening into place."))
		play_sfx(src, SFX_MACHINES_CLICK)
		user.drop_item()
		src.forceMove(M)
		src.machine_handle = om_handle(M)
	else
		act_message(user, src, MSG_SELF("There aren't any ports on [M] that match the jack belonging to %T%."), MSG_OTHERS("%U% fumbles to find a place on [M] to plug in %T%."))

/obj/item/pai_cable/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	return NONE
