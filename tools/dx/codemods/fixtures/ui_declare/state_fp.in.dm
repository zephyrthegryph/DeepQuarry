/obj/machinery/guarded
	name = "guarded"

DECLARE_UI(/obj/machinery/guarded, "Guarded")
DECLARE_UI_STATE(/obj/machinery/guarded, GLOB.tgui_physical_state)

/obj/machinery/guarded/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/machinery/guarded, "go", ui_act_go)
UI_ACT_PROC(/obj/machinery/guarded, ui_act_go)
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
