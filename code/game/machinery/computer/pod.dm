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
// Keyed by id: linked when either end materializes (replaces the LateInitialize and per-use scans).
/obj/machinery/computer/pod/relations()
	. = ..()
	. += rel_one(nameof(connected), keyed = nameof(id), keyed_target = /obj/machinery/mass_driver)
	. += rel_many(nameof(pod_doors), keyed = nameof(id), keyed_target = /obj/machinery/door/blast)
	. += rel_many(nameof(pod_drivers), keyed = nameof(id), keyed_target = /obj/machinery/mass_driver)

/obj/machinery/computer/pod/proc/alarm()
	if(!operable())
		return

	if(!( connected() ))
		to_chat(viewers(null, null),"Cannot locate mass driver connector. Cancelling firing sequence!")
		return

	for(var/obj/machinery/door/blast/M as anything in pod_doors)
		M.open()

	after(src, 2 SECONDS, PROC_REF(alarm_drive))

/obj/machinery/computer/pod/proc/alarm_drive()
	for(var/obj/machinery/mass_driver/M as anything in pod_drivers)
		M.power = connected()?.power
		M.drive()
	after(src, 5 SECONDS, PROC_REF(alarm_close))

/obj/machinery/computer/pod/proc/alarm_close()
	for(var/obj/machinery/door/blast/M as anything in pod_doors)
		M.close()
		return

/obj/machinery/computer/pod/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	if(!Adjacent(user) && !(A.authority & AUTH_REMOTE_ACCESS)) // out of reach, and not over a remote link
		return TRUE
	tgui_interact(user)
	return TRUE

CAPABILITIES(/obj/machinery/computer/pod)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(timing), gate = PROC_REF(operable), wakes_on = list(nameof(timing), nameof(stat)))
	interface("PodComputer")
	op("toggle_door", ui_act("toggle_door"), then(PROC_REF(ui_act_toggle_door)))
	op("start_stop", ui_act("start_stop"), then(PROC_REF(ui_act_start_stop)))
	op("test_alarm", ui_act("test_alarm"), then(PROC_REF(ui_act_test_alarm)))
	op("test_drive", ui_act("test_drive"), then(PROC_REF(ui_act_test_drive)))
	op("adjust_power", ui_act("adjust_power", arg("value", num())), then(PROC_REF(ui_act_adjust_power)))
	op("adjust_time", ui_act("adjust_time", arg("value", num())), then(PROC_REF(ui_act_adjust_time)))
	op("open_ui_impl", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_open_ui_impl)))

/obj/machinery/computer/pod/ui_title(mob/user)
	return title

/obj/machinery/computer/pod/ui_data(datum/act/eval/A)

	return list(
		"connected" = connected(),
		"timing" = timing,
		"time" = time,
		"power_level" = connected()?.power
	)

/obj/machinery/computer/pod/proc/ui_act_toggle_door(datum/act/op/A)
	for(var/obj/machinery/door/blast/M as anything in pod_doors)
		if(M.density)
			M.open()
		else
			M.close()
	return TRUE

/obj/machinery/computer/pod/proc/ui_act_start_stop(datum/act/op/A)
	set_timing(!timing)
	return TRUE

/obj/machinery/computer/pod/proc/ui_act_test_alarm(datum/act/op/A)
	alarm()
	return TRUE

/obj/machinery/computer/pod/proc/ui_act_test_drive(datum/act/op/A)
	for(var/obj/machinery/mass_driver/M as anything in pod_drivers)
		M.power = connected()?.power
		M.drive()
	return TRUE

/obj/machinery/computer/pod/proc/ui_act_adjust_power(datum/act/op/A, value)
	if(!connected())
		return FALSE
	connected().power = CLAMP(value, 0.25, 16)
	return TRUE

/obj/machinery/computer/pod/proc/ui_act_adjust_time(datum/act/op/A, value)
	time = CLAMP(round(value), 0, 120)
	return TRUE

/obj/machinery/computer/pod/proc/work_step(datum/act/timer/A)
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

EXTEND_INTERACTIONS(/obj/machinery/computer/pod/old/syndicate, \
	INTERACT_HAND("Use", PROC_REF(interaction_open_ui_impl), REQ_ON(PRED_ACTOR, /obj/machinery/computer/pod/old/syndicate/proc/lets_in, "access denied")), \
)

/obj/machinery/computer/pod/old/syndicate/proc/lets_in(mob/actor, atom/target, obj/item/held)
	return allowed(actor)

/obj/machinery/computer/pod/old/swf
	name = "Magix System IV"
	desc = "An arcane artifact that holds much magic. Running E-Knock 2.2: Sorceror's Edition"

/// connected (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/pod/proc/connected() as /obj/machinery/mass_driver
	return connected
