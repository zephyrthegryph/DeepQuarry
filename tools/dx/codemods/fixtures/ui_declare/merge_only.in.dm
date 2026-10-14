DECLARE_UI(/obj/machinery/plain, "Plain")

UI_DATA_REPLACE(/obj/machinery/plain, "merge:ui_data_plain{a:num}")

/obj/machinery/plain/proc/ui_data_plain(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list("a" = 1)
	data["who"] = "[user]"
	return data

CAPABILITIES(/obj/machinery/plain)
	examine_line("It is plain.")

UI_ACT(/obj/machinery/plain, "go", ui_act_go)
UI_ACT_PROC(/obj/machinery/plain, ui_act_go)
	return FALSE
