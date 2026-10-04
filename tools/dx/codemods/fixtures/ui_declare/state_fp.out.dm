/obj/machinery/guarded
	name = "guarded"

CAPABILITIES(/obj/machinery/guarded)
	interface("Guarded", state = nameof(GLOB.tgui_physical_state))
	op("go", ui_act("go"), then(PROC_REF(ui_act_go)))

/obj/machinery/guarded/proc/ui_act_go(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(A.actor)
	to_chat(user, "went")
	return TRUE

/obj/machinery/checked
	name = "checked"

DECLARE_UI(/obj/machinery/checked, "Checked")

/obj/machinery/checked/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(user.stat)
		return FALSE
	return TRUE

UI_ACT(/obj/machinery/checked, "go", ui_act_go)
UI_ACT_PROC(/obj/machinery/checked, ui_act_go)
	return TRUE
