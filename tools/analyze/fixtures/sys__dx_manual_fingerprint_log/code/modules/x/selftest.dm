
/obj/machinery/pump/proc/act_toggle(mob/user)
	add_fingerprint(user)
	log_game("[user] toggled [src]")
	return TRUE

/obj/machinery/pump/capabilities()
	. = ..()
	. += cap_hand("Toggle", PROC_REF(toggle_power))
	. += cap_tool("Unbolt", TOOL_WRENCH, handler = TYPE_PROC_REF(/obj/machinery, unbolt))

/obj/machinery/pump/proc/toggle_power(mob/user)
	message_admins("[user] toggled [src]")
	return TRUE

/obj/machinery/proc/unbolt(mob/user, obj/item/held)
	log_admin("unbolted")
	return TRUE

/obj/machinery/pump/proc/helper(mob/user)
	add_fingerprint(user)

/obj/item/other/proc/toggle_power(mob/user)
	log_game("unrelated type")

/proc/act_message_like(user)
	log_game("a global proc named act_*")
