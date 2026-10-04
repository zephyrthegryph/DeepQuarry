/obj/machinery/lamp
	name = "lamp"

DECLARE_UI(/obj/machinery/lamp, "Lamp")

UI_ACT(/obj/machinery/lamp, "pick", ui_act_pick)
UI_ACT_PROC(/obj/machinery/lamp, ui_act_pick)
	var/obj/item/A = user.get_active_hand()
	if(A && A.name != "A")
		to_chat(user, "kept [A] as A.name")
	return TRUE
