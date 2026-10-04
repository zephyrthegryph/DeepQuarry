CAPABILITIES(/obj/machinery/stately)
	interface("Stately", state = nameof(GLOB.tgui_always_state))
	op("go", ui_act("go"), then(PROC_REF(ui_act_go)))
/obj/machinery/stately/proc/ui_act_go(datum/act/op/A)
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

/obj/machinery/gap_late

DECLARE_UI(/obj/machinery/gap_late, "GapLate")

UI_ACT(/obj/machinery/gap_late, "later", ui_act_later)
UI_ACT_PROC(/obj/machinery/gap_late, ui_act_later)
	var/ok = prob(50)
	var/_answer_a3 = act_ask(ui.user, action, params, ui, "a3", /datum/om/prompt/text, message = "Name?")
	if(isnull(_answer_a3))
		return
	return TRUE
