/obj/machinery/thing/emag_act(remaining_charges, mob/user)
	return 1

/obj/machinery/thing/proc/poke(mob/user)
	var/obj/item/card/emag/E = user.get_active_hand()
	E.emag_act(1, user)
	on_emag(1, user)
	thing.on_emag(1, user, E)
	other?.on_emag(1)
	list(PROC_REF(on_emag))
	emag_target(src, 1, user, E)
	used_uses += 1
	// emag_act in a comment is ignored
	to_chat(user, "emag_act in a string is still counted by this module")
	on_emag(1, user) // ALLOW(sys_emag_act): this call is the one the gate makes for itself

/obj/machinery/thing/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	. = ..()
	return 1

/obj/machinery/thing/proc/on_emag(remaining_charges, mob/user)
	return 1
