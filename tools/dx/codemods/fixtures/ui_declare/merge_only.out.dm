/obj/machinery/plain/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list("a" = 1)
	data["who"] = "[user]"
	return data

CAPABILITIES(/obj/machinery/plain)
	examine_line("It is plain.")
	interface("Plain")
	without("ui_open")
	op("go", ui_act("go"), then(PROC_REF(ui_act_go)))

/obj/machinery/plain/proc/ui_act_go(datum/act/op/A)
	return FALSE
