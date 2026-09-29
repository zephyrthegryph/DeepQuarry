//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

/obj/machinery/computer/pod
	name = "pod launch control console"
	desc = "A control console for launching pods. Some people prefer firing Mechas."
	icon_screen = "mass_driver"
	light_color = "#00b000"
	circuit = /obj/item/circuitboard/pod
	var/id = 1.0
	var/obj/machinery/mass_driver/connected
	var/time = 30.0
	var/title = "Mass Driver Controls"

/// Blast doors and mass drivers sharing our id.
/obj/machinery/computer/pod/var/list/obj/machinery/door/blast/pod_doors
/obj/machinery/computer/pod/var/list/obj/machinery/mass_driver/pod_drivers

OM_FIELD(/obj/machinery/computer/pod, timing, FALSE, CHANGE_MACHINE_SETTINGS)
DECLARE_PERIODIC_WHILE_ALL(/obj/machinery/computer/pod, MACHINE_PIPELINE, list("timing", "operable"))

// Keyed by id: linked when either end materializes (replaces the LateInitialize and per-use scans).
REL_KEYED(/obj/machinery/computer/pod, connected, id, /obj/machinery/mass_driver)
REL_KEYED_LIST(/obj/machinery/computer/pod, pod_doors, id, /obj/machinery/door/blast)
REL_KEYED_LIST(/obj/machinery/computer/pod, pod_drivers, id, /obj/machinery/mass_driver)

/obj/machinery/computer/pod/proc/alarm()
	if(!operable())
		return

	if(!( connected() ))
		to_chat(viewers(null, null),"Cannot locate mass driver connector. Cancelling firing sequence!")
		return

	for(var/obj/machinery/door/blast/M as anything in pod_doors)
		M.open()

	om_after(src, 2 SECONDS, PROC_REF(alarm_drive))

/obj/machinery/computer/pod/proc/alarm_drive()
	for(var/obj/machinery/mass_driver/M as anything in pod_drivers)
		M.power = connected()?.power
		M.drive()
	om_after(src, 5 SECONDS, PROC_REF(alarm_close))

/obj/machinery/computer/pod/proc/alarm_close()
	for(var/obj/machinery/door/blast/M as anything in pod_doors)
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

/obj/machinery/computer/pod/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	. = ..()

	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PodComputer", title)
		ui.open()

/obj/machinery/computer/pod/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)

	return list(
		"connected" = connected(),
		"timing" = timing,
		"time" = time,
		"power_level" = connected()?.power
	)

/obj/machinery/computer/pod/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return

	switch(action)
		if("toggle_door")
			for(var/obj/machinery/door/blast/M as anything in pod_doors)
				if(M.density)
					M.open()
				else
					M.close()
			return TRUE
		if("start_stop")
			set_timing(!timing)
			return TRUE
		if("test_alarm")
			alarm()
			return TRUE
		if("test_drive")
			for(var/obj/machinery/mass_driver/M as anything in pod_drivers)
				M.power = connected()?.power
				M.drive()
			return TRUE
		if("adjust_power")
			if(!connected())
				return FALSE
			connected().power = CLAMP(text2num(params["value"]), 0.25, 16)
			return TRUE
		if("adjust_time")
			time = CLAMP(round(text2num(params["value"])), 0, 120)
			return TRUE

/obj/machinery/computer/pod/machine_step()
	if(time > 0)
		time = round(time) - 1
	else
		alarm()
		time = 0
		set_timing(FALSE)

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

/// connected (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/pod/proc/connected() as /obj/machinery/mass_driver
	return connected
