/obj/machinery/namer
	name = "namer"

DECLARE_UI(/obj/machinery/namer, "Namer")

UI_ACT(/obj/machinery/namer, "rename", ui_act_rename, UI_ARG_VALUE("name"))
UI_ACT_PROC(/obj/machinery/namer, ui_act_rename)
	to_chat(user, "was [name], now [params["name"]]")
	return TRUE
