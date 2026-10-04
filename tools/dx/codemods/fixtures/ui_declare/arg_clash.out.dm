/obj/machinery/namer
	name = "namer"

CAPABILITIES(/obj/machinery/namer)
	interface("Namer")
	op("rename", ui_act("rename", arg("name")), then(PROC_REF(ui_act_rename)))

/obj/machinery/namer/proc/ui_act_rename(datum/act/op/A, name_arg)
	var/mob/user = A.actor
	to_chat(user, "was [name], now [name_arg]")
	return TRUE
