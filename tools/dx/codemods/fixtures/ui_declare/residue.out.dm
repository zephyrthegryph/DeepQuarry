DECLARE_UI(/obj/machinery/stately, "Stately")
DECLARE_UI_STATE(/obj/machinery/stately, GLOB.tgui_always_state)
UI_ACT(/obj/machinery/stately, "go", ui_act_go)
UI_ACT_PROC(/obj/machinery/stately, ui_act_go)
	return TRUE

DECLARE_UI(/obj/machinery/greedy, "Greedy")
UI_ACT(/obj/machinery/greedy, "go", greedy_go)
UI_ACT_PROC(/obj/machinery/greedy, greedy_go)
	ui.close()
	return TRUE

DECLARE_UI(/obj/machinery/choosy, "Choosy")
UI_ACT(/obj/machinery/choosy, "go", choosy_go, UI_ARG_CHOICE("c", list("a")))
UI_ACT_PROC(/obj/machinery/choosy, choosy_go)
	return TRUE

DECLARE_UI(/obj/machinery/guarded, "Guarded")
UI_ACT(/obj/machinery/guarded, "go", guarded_go)
UI_ACT_PROC(/obj/machinery/guarded, guarded_go)
	return TRUE
/obj/machinery/guarded/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	return TRUE
