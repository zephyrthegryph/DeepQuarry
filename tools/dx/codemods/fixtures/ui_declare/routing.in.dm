/obj/machinery/gap_ctl
	var/list/valid_actions = list("dock", "undock")
	var/obj/machinery/gap_unit/unit
	var/mode = 0

DECLARE_UI(/obj/machinery/gap_ctl, "GapCtl", UI_TITLE("Gap controller"))

/// The window is the unit's panel: every button goes to the unit.
UI_ACT_FORWARD(/obj/machinery/gap_ctl, ui_forward_to_unit)
/obj/machinery/gap_ctl/proc/ui_forward_to_unit(mob/user, action)
	return unit

/// The controller's actions are its program's commands.
UI_ACT_FALLBACK(/obj/machinery/gap_ctl, ui_act_program_command)
UI_ACT_PROC(/obj/machinery/gap_ctl, ui_act_program_command)
	if(user)
		add_fingerprint(user)
	if(!(action in valid_actions))
		return FALSE
	mode = action
	return TRUE

UI_ACT(/obj/machinery/gap_ctl, "reset", ui_act_reset, UI_ARG_NUM("level", 0, 10))
UI_ACT_PROC(/obj/machinery/gap_ctl, ui_act_reset)
	mode = params["level"]
	return TRUE

/obj/machinery/gap_ctl/locked

UI_ACT_OVERRIDE(/obj/machinery/gap_ctl/locked, ui_act_reset)
	if(params["level"] > 5)
		return
	mode = 0
