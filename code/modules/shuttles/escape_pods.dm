/datum/shuttle/autodock/ferry/escape_pod
	var/tmp/datum/embedded_program/docking/simple/escape_pod_berth/arming_controller
	category = /datum/shuttle/autodock/ferry/escape_pod

/datum/shuttle/autodock/ferry/escape_pod/New()
	move_time = move_time + rand(-30, 60)
	if(name in SSemergency_shuttle.escape_pods)
		CRASH("An escape pod with the name '[name]' has already been defined.")
	SSemergency_shuttle.escape_pods[name] = src

	..()

	// base shuttle New() may have early-returned without setting
	// current_location (landmark missing). Skip the arming-controller
	// lookup so we don't trip the null deref / spurious CRASH below.
	if(!current_location())
		return

	//find the arming controller (berth) - If not configured directly, try to read it from current location landmark
	var/arming_controller_tag = arming_controller()
	if(!arming_controller() && active_docking_controller())
		arming_controller_tag = active_docking_controller().id_tag
	rel_set(src, nameof(arming_controller), shuttles_docking_registry()[arming_controller_tag])
	if(!istype(arming_controller(), /datum/embedded_program/docking/simple/escape_pod_berth))
		CRASH("Could not find arming controller for escape pod \"[name]\", tag was '[arming_controller_tag]'.")
	// Every pod names the shared berth program through a relation view, cleared when the
	// program is deleted: no QDELETING registration.

	//find the pod's own controller
	var/datum/embedded_program/docking/simple/prog = shuttles_docking_registry()[docking_controller_tag]
	var/obj/machinery/embedded_controller/radio/simple_docking_controller/escape_pod/controller_master = prog.master
	if(!istype(controller_master))
		CRASH("Escape pod \"[name]\" could not find it's controller master! docking_controller_tag=[docking_controller_tag]")
	rel_set(controller_master, nameof(controller_master.pod), src)

/datum/shuttle/autodock/ferry/escape_pod/can_launch()
	if(arming_controller() && !arming_controller().armed)	//must be armed
		return 0
	if(location)
		return 0	//it's a one-way trip.
	return ..()

/datum/shuttle/autodock/ferry/escape_pod/can_force()
	if (arming_controller().eject_time && ELAPSED(arming_controller(), eject_time, CLOCK_WORLD) < 5 SECONDS)
		return 0	//dont allow force launching until 5 seconds after the arming controller has reached it's countdown
	return ..()

/datum/shuttle/autodock/ferry/escape_pod/can_cancel()
	return 0

//This controller goes on the escape pod itself
/obj/machinery/embedded_controller/radio/simple_docking_controller/escape_pod
	name = "escape pod controller"
	unacidable = TRUE
	program = /datum/embedded_program/docking/simple
	var/tmp/datum/shuttle/autodock/ferry/escape_pod/pod
	valid_actions = list("toggle_override", "force_door")

/// The window's data.
/obj/machinery/embedded_controller/radio/simple_docking_controller/escape_pod/ui_data(datum/act/eval/A)
	var/datum/embedded_program/docking/simple/docking_program = program // Cast to proper type

	. = list(
		"docking_status" = docking_program.get_docking_status(),
		"override_enabled" = docking_program.override_enabled,
		"exterior_status" =	docking_program.memory["door_status"],								// TGUI DATA fails silently when there's no linked pod, leading to UI crashes
		"can_force" = pod()?.can_force() || (SSemergency_shuttle.departed && pod()?.can_launch()),	//allow players to manually launch ahead of time if the shuttle leaves
		"armed" = pod()?.arming_controller().armed,
		"internalTemplateName" = "EscapePodConsole",
	)

CAPABILITIES(/obj/machinery/embedded_controller/radio/simple_docking_controller/escape_pod)
	op("manual_arm", ui_act("manual_arm"), then(PROC_REF(ui_act_manual_arm)))
	op("force_launch", ui_act("force_launch"), then(PROC_REF(ui_act_force_launch)))

/obj/machinery/embedded_controller/radio/simple_docking_controller/escape_pod/proc/ui_act_manual_arm(datum/act/op/A)
	pod().arming_controller().arm()
	. = TRUE

/obj/machinery/embedded_controller/radio/simple_docking_controller/escape_pod/proc/ui_act_force_launch(datum/act/op/A)
	if(pod().can_force())
		pod().force_launch(src)
	else if(SSemergency_shuttle.departed && pod().can_launch())	//allow players to manually launch ahead of time if the shuttle leaves
		pod().launch(src)
	. = TRUE

//This controller is for the escape pod berth (station side)
/obj/machinery/embedded_controller/radio/simple_docking_controller/escape_pod_berth
	name = "escape pod berth controller"
	program = /datum/embedded_program/docking/simple/escape_pod_berth
	valid_actions = list("toggle_override", "force_door")

/// The window's data.
/obj/machinery/embedded_controller/radio/simple_docking_controller/escape_pod_berth/ui_data(datum/act/eval/A)
	var/datum/embedded_program/docking/simple/docking_program = program // Cast to proper type

	var/armed = null
	if(istype(docking_program, /datum/embedded_program/docking/simple/escape_pod_berth))
		var/datum/embedded_program/docking/simple/escape_pod_berth/P = docking_program
		armed = P.armed

	. = list(
		"docking_status" = docking_program.get_docking_status(),
		"override_enabled" = docking_program.override_enabled,
		"exterior_status" =	docking_program.memory["door_status"],
		"armed" = armed,
		"internalTemplateName" = "EscapePodBerthConsole",
	)

CAPABILITIES(/obj/machinery/embedded_controller/radio/simple_docking_controller/escape_pod_berth)
	emag(then(PROC_REF(on_emag)), powered = FALSE)

/obj/machinery/embedded_controller/radio/simple_docking_controller/escape_pod_berth/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You emag the [src], arming the escape pod!"))
	set_emagged(1)
	if (istype(program, /datum/embedded_program/docking/simple/escape_pod_berth))
		var/datum/embedded_program/docking/simple/escape_pod_berth/P = program
		if (!P.armed)
			P.arm()
	return OP_OK

//A docking controller program for a simple door based docking port
/datum/embedded_program/docking/simple/escape_pod_berth
	var/armed = 0
	var/eject_delay = 10	//give latecomers some time to get out of the way if they don't make it onto the pod
	EXPIRY_DECLARE(eject_time)
	var/closing = 0

/datum/embedded_program/docking/simple/escape_pod_berth/proc/arm()
	if(!armed)
		armed = 1
		open_door()

/datum/embedded_program/docking/simple/escape_pod_berth/receive_user_command(command)
	if (!armed)
		return TRUE // Eat all commands.
	return ..(command)

/// after() callback from prepare_for_undocking(): the latecomers' grace is over.
/datum/embedded_program/docking/simple/escape_pod_berth/proc/eject_timer_fired()
	if(!closing)
		close_door()
		closing = 1

/datum/embedded_program/docking/simple/escape_pod_berth/prepare_for_docking()
	return

/datum/embedded_program/docking/simple/escape_pod_berth/ready_for_docking()
	return 1

/datum/embedded_program/docking/simple/escape_pod_berth/finish_docking()
	return		//don't do anything - the doors only open when the pod is armed.

/datum/embedded_program/docking/simple/escape_pod_berth/prepare_for_undocking()
	EXPIRY_SET(src, eject_time, eject_delay*10, CLOCK_WORLD)
	after(src, eject_delay*10, PROC_REF(eject_timer_fired))

/// Accessor for the arming_controller var.
/datum/shuttle/autodock/ferry/escape_pod/proc/arming_controller() as /datum/embedded_program/docking/simple/escape_pod_berth
	return arming_controller

/// Accessor for the pod var.
/obj/machinery/embedded_controller/radio/simple_docking_controller/escape_pod/proc/pod() as /datum/shuttle/autodock/ferry/escape_pod
	return pod
