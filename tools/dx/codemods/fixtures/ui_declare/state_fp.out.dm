/obj/machinery/guarded
	name = "guarded"

CAPABILITIES(/obj/machinery/guarded)
	interface("Guarded", state = nameof(GLOB.tgui_physical_state))
	without("ui_open")
	op("go", ui_act("go"), then(PROC_REF(ui_act_go)))

/obj/machinery/guarded/proc/ui_act_go(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(A.actor)
	to_chat(user, "went")
	return TRUE

/obj/machinery/checked
	name = "checked"

CAPABILITIES(/obj/machinery/checked)
	interface("Checked")
	without("ui_open")
	op("go", ui_act("go"), then(PROC_REF(ui_act_go)))

/obj/machinery/checked/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(user.stat)
		return FALSE
	return TRUE

/obj/machinery/checked/proc/ui_act_go(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	return TRUE
