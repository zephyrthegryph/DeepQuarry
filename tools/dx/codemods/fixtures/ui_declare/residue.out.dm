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

CAPABILITIES(/obj/machinery/choosy)
	interface("Choosy")
	op("go", ui_act("go", arg("c")), then(PROC_REF(choosy_go)))
/obj/machinery/choosy/proc/choosy_go(datum/act/op/A, c)
	if(!isnull(c) && !(c in list("a")))
		return FALSE
	return TRUE

CAPABILITIES(/obj/machinery/guarded)
	interface("Guarded")
	op("go", ui_act("go"), then(PROC_REF(guarded_go)))
/obj/machinery/guarded/proc/guarded_go(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	return TRUE
/obj/machinery/guarded/proc/ui_gate(datum/act/op/A)
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
