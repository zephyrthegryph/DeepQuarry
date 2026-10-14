/obj/machinery/gizmo
	var/power = 0
	var/mode = 0

MSG_DEF_SELF(gizmo/done, "Done.")

CAPABILITIES(/obj/machinery/gizmo)
	interface("Gizmo", title = "Gizmo Control")
	without("ui_open")
	op("toggle", ui_act("toggle"), then(PROC_REF(ui_act_toggle)))
	op("set-level", ui_act("set-level", arg("level", num(0, 10)), arg("target")), then(PROC_REF(ui_act_level)))
	op("name", ui_act("name", arg("label", schema_text(4096)), arg("count", int())), then(PROC_REF(ui_act_name)))

/obj/machinery/gizmo/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["power"] = power
	data["shown"] = mode
	data["level"] = level_of(A.actor, null, null)
	var/list/merged_1 = ui_data_gizmo(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/obj/machinery/gizmo/proc/level_of(mob/user, datum/tgui/ui, datum/tgui_state/state)
	return power + 1

/obj/machinery/gizmo/proc/ui_data_gizmo(mob/user, datum/tgui/ui, datum/tgui_state/state)
	return list("more" = isliving(user))

/obj/machinery/gizmo/proc/ui_act_toggle(datum/act/op/A)
	power = !power
	. = TRUE

/obj/machinery/gizmo/proc/ui_act_level(datum/act/op/A, level, target)
	EVENT_HANDLER
	var/mob/user = A.actor
	// who is asking, and what for
	to_chat(user, "level [level] for [target]")
	mode = level

/obj/machinery/gizmo/proc/ui_act_name(datum/act/op/A, label, count)
	name = label
	mode = count
	return TRUE
