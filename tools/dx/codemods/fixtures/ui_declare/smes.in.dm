/obj/machinery/gizmo
	var/power = 0
	var/mode = 0

MSG_DEF_SELF(gizmo/done, "Done.")

DECLARE_UI(/obj/machinery/gizmo, "Gizmo", UI_TITLE("Gizmo Control"))

UI_DATA_REPLACE(/obj/machinery/gizmo, "power", "shown=mode:num", "level=proc:level_of", "merge:ui_data_gizmo{more:num}")

/obj/machinery/gizmo/proc/level_of(mob/user, datum/tgui/ui, datum/tgui_state/state)
	return power + 1

/obj/machinery/gizmo/proc/ui_data_gizmo(mob/user, datum/tgui/ui, datum/tgui_state/state)
	return list("more" = isliving(user))

UI_ACT(/obj/machinery/gizmo, "toggle", ui_act_toggle)
UI_ACT_PROC(/obj/machinery/gizmo, ui_act_toggle)
	power = !power
	. = TRUE

UI_ACT(/obj/machinery/gizmo, "set-level", ui_act_level, UI_ARG_NUM("level", 0, 10), UI_ARG_VALUE("target"))
UI_ACT_PROC(/obj/machinery/gizmo, ui_act_level)
	EVENT_HANDLER
	// who is asking, and what for
	to_chat(user, "level [params["level"]] for [params["target"]]")
	mode = params["level"]

UI_ACT(/obj/machinery/gizmo, "name", ui_act_name, UI_ARG_TEXT("label"), UI_ARG_INT("count"))
UI_ACT_PROC(/obj/machinery/gizmo, ui_act_name)
	name = params["label"]
	mode = params["count"]
	return TRUE
