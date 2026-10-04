/obj/machinery/gap_ctl
	var/list/valid_actions = list("dock", "undock")
	var/obj/machinery/gap_unit/unit
	var/mode = 0

CAPABILITIES(/obj/machinery/gap_ctl)
	interface("GapCtl", title = "Gap controller", forwards = nameof(unit))
	op("program_command", ui_act("*"), then(PROC_REF(ui_act_program_command)))
	op("reset", ui_act("reset", arg("level", num(0, 10))), then(PROC_REF(ui_act_reset)))

/// The controller's actions are its program's commands.
/obj/machinery/gap_ctl/proc/ui_act_program_command(datum/act/op/A)
	var/mob/user = A.actor
	var/action = A.window_action()
	if(user)
		add_fingerprint(user)
	if(!(action in valid_actions))
		return FALSE
	mode = action
	return TRUE

/obj/machinery/gap_ctl/proc/ui_act_reset(datum/act/op/A, level)
	mode = level
	return TRUE

/obj/machinery/gap_ctl/locked

/obj/machinery/gap_ctl/locked/ui_act_reset(datum/act/op/A, level)
	if(level > 5)
		return
	mode = 0
