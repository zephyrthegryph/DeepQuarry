/obj/machinery/lamp
	name = "lamp"

CAPABILITIES(/obj/machinery/lamp)
	interface("Lamp")
	op("pick", ui_act("pick"), then(PROC_REF(ui_act_pick)))

/obj/machinery/lamp/proc/ui_act_pick(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/A2 = user.get_active_hand()
	if(A2 && A2.name != "A")
		to_chat(user, "kept [A2] as A.name")
	return TRUE
