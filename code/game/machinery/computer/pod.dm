//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

/obj/machinery/computer/pod
	name = "pod launch control console"
	desc = "A control console for launching pods. Some people prefer firing Mechas."
	icon_screen = "mass_driver"
	light_color = "#00b000"
	circuit = /obj/item/circuitboard/pod
	var/id = 1.0
	var/connected_handle
	var/timing = FALSE
	var/time = 30.0
	var/title = "Mass Driver Controls"

/obj/machinery/computer/pod/Initialize(mapload)
	..()
	return INITIALIZE_HINT_LATELOAD

/obj/machinery/computer/pod/LateInitialize()
	for(var/obj/machinery/mass_driver/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id == id)
			connected_handle = om_handle(M)
			break

/obj/machinery/computer/pod/proc/alarm()
	if(!operable())
		return

	if(!( connected() ))
		to_chat(viewers(null, null),"Cannot locate mass driver connector. Cancelling firing sequence!")
		return

	for(var/obj/machinery/door/blast/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id == id)
			M.open()

	om_after(src, 2 SECONDS, PROC_REF(alarm_drive))

/obj/machinery/computer/pod/proc/alarm_drive()
	for(var/obj/machinery/mass_driver/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id == id)
			M.power = connected()?.power
			M.drive()
	om_after(src, 5 SECONDS, PROC_REF(alarm_close))

/obj/machinery/computer/pod/proc/alarm_close()
	for(var/obj/machinery/door/blast/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id == id)
			M.close()
			return

/obj/machinery/computer/pod/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/pod_open_ui,
	)
	..()

/datum/interaction/machine_hand/pod_open_ui
	id = "pod_open_ui"
	name = "Use"
	effect = /obj/machinery/computer/pod/proc/interaction_open_ui_impl

/obj/machinery/computer/pod/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	if(!Adjacent(user) && !issilicon(user))
		return TRUE
	tgui_interact(user)
	return TRUE

DECLARE_UI(/obj/machinery/computer/pod, "PodComputer")

/obj/machinery/computer/pod/ui_title(mob/user)
	return title

/obj/machinery/computer/pod/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)

	return list(
		"connected" = connected(),
		"timing" = timing,
		"time" = time,
		"power_level" = connected()?.power
	)

UI_ACT(/obj/machinery/computer/pod, "toggle_door", ui_act_toggle_door)
UI_ACT_PROC(/obj/machinery/computer/pod, ui_act_toggle_door)
	for(var/obj/machinery/door/blast/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id == id)
			if(M.density)
				M.open()
			else
				M.close()
	return TRUE

UI_ACT(/obj/machinery/computer/pod, "start_stop", ui_act_start_stop)
UI_ACT_PROC(/obj/machinery/computer/pod, ui_act_start_stop)
	timing = !timing
	if(timing)
		MACHINE_WAKE(src)
	return TRUE

UI_ACT(/obj/machinery/computer/pod, "test_alarm", ui_act_test_alarm)
UI_ACT_PROC(/obj/machinery/computer/pod, ui_act_test_alarm)
	alarm()
	return TRUE

UI_ACT(/obj/machinery/computer/pod, "test_drive", ui_act_test_drive)
UI_ACT_PROC(/obj/machinery/computer/pod, ui_act_test_drive)
	for(var/obj/machinery/mass_driver/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id == id)
			M.power = connected().power
			M.drive()
	return TRUE

UI_ACT(/obj/machinery/computer/pod, "adjust_power", ui_act_adjust_power, UI_ARG_NUM("value"))
UI_ACT_PROC(/obj/machinery/computer/pod, ui_act_adjust_power)
	if(!connected())
		return FALSE
	connected().power = CLAMP(params["value"], 0.25, 16)
	return TRUE

UI_ACT(/obj/machinery/computer/pod, "adjust_time", ui_act_adjust_time, UI_ARG_NUM("value"))
UI_ACT_PROC(/obj/machinery/computer/pod, ui_act_adjust_time)
	time = CLAMP(round(params["value"]), 0, 120)
	return TRUE

/obj/machinery/computer/pod/machine_step()
	if(!operable())
		return PROCESS_KILL
	if(!timing)
		return PROCESS_KILL
	if(time > 0)
		time = round(time) - 1
	else
		alarm()
		time = 0
		timing = FALSE
		return PROCESS_KILL

/obj/machinery/computer/pod/power_change()
	. = ..()
	// machine_step() sleeps on NOPOWER; resume the countdown when power returns.
	if(timing && operable())
		MACHINE_WAKE(src)

/obj/machinery/computer/pod/old
	icon_state = "oldcomp"
	icon_keyboard = null
	icon_screen = "library"
	name = "DoorMex Control Computer"
	title = "Door Controls"

/obj/machinery/computer/pod/old/syndicate
	name = "ProComp Executive IIc"
	desc = "Criminals often operate on a tight budget. Operates external airlocks."
	title = "External Airlock Controls"
	req_access = list(ACCESS_SYNDICATE)

/obj/machinery/computer/pod/old/syndicate/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/pod_syndicate_open_ui,
	)
	..()

/datum/interaction/machine_hand/pod_syndicate_open_ui
	id = "pod_syndicate_open_ui"
	name = "Use"
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null), REQ_ON(PRED_ACTOR, /obj/machinery/computer/pod/old/syndicate/proc/lets_in, "access denied"))
	effect = /obj/machinery/computer/pod/proc/interaction_open_ui_impl

/obj/machinery/computer/pod/old/syndicate/proc/lets_in(mob/actor, atom/target, obj/item/held)
	return allowed(actor)

/obj/machinery/computer/pod/old/swf
	name = "Magix System IV"
	desc = "An arcane artifact that holds much magic. Running E-Knock 2.2: Sorceror's Edition"

/// LC-refs: connected -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/computer/pod/proc/connected() as /obj/machinery/mass_driver
	return om_resolve(connected_handle)
