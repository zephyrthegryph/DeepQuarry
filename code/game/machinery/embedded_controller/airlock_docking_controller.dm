/*
 * NOTE - This file defines both these datums: Yes, you read that right.  Its confusing.  Lets try and break it down.
 *  /datum/embedded_program/docking/airlock
 *		- A docking controller for an airlock based docking port
 *  /datum/embedded_program/airlock/docking
 *		- An extension to the normal airlock program allows disabling of the regular airlock functions when docking
*/

//a docking port based on an airlock
/obj/machinery/embedded_controller/radio/airlock/docking_port
	name = "docking port controller"
	var/datum/embedded_program/airlock/docking/airlock_program
	var/datum/embedded_program/docking/airlock/docking_program
	var/display_name		// For mappers to override docking_program.display_name (how would it show up on docking monitoring program)
	tag_secure = 1
	valid_actions = list("cycle_ext", "cycle_int", "force_ext", "force_int", "abort", "toggle_override")

CAPABILITIES(/obj/machinery/embedded_controller/radio/airlock/docking_port)
	owns_one(nameof(program), /datum/embedded_program, starts = PROC_REF(make_docking_program))
	owns_one(nameof(airlock_program), starts = /datum/embedded_program/airlock/docking)
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(multitool_used)))

// ALLOW(init/INSTANCE_STATE): its docking program is made from the program tag and name the map set
/obj/machinery/embedded_controller/radio/airlock/docking_port/Initialize(mapload)
	. = ..()
	// The port owns its running program (program, owns_one(starts =)); docking_program is a typed view of it.
	rel_set(src, nameof(docking_program), program)
	if(display_name)
		docking_program.display_name = display_name

/obj/machinery/embedded_controller/radio/airlock/docking_port/proc/multitool_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	var/datum/embedded_program/docking/airlock/docking_program = program
	var/code = docking_program.docking_codes
	code = code ? stars(code) : "N/A"
	to_chat(user, "[tool]'s screen displays '[code]'")
	return OP_OK

/// The window's data.
/obj/machinery/embedded_controller/radio/airlock/docking_port/ui_data(datum/act/eval/A)
	var/datum/embedded_program/docking/airlock/docking_program = program
	var/datum/embedded_program/airlock/docking/airlock_program = docking_program.airlock_program

	. = list(
		"chamber_pressure" = round(airlock_program.memory["chamber_sensor_pressure"]),
		"exterior_status" = airlock_program.memory["exterior_status"],
		"interior_status" = airlock_program.memory["interior_status"],
		"processing" = airlock_program.memory["processing"],
		"docking_status" = docking_program.get_docking_status(),
		"airlock_disabled" = !(docking_program.undocked() || docking_program.override_enabled),
		"override_enabled" = docking_program.override_enabled,
		"docking_codes" = docking_program.docking_codes,
		"name" = docking_program.get_name(),
		"internalTemplateName" = "AirlockConsoleDocking",
	)

///////////////////////////////////////////////////////////////////////////////
//A docking controller for an airlock based docking port
//
/datum/embedded_program/docking/airlock
	var/datum/embedded_program/airlock/docking/airlock_program

/datum/embedded_program/docking/airlock/New(obj/machinery/embedded_controller/M, datum/embedded_program/airlock/docking/A)
	..(M)
	rel_set(src, nameof(airlock_program), A)
	rel_set(airlock_program, nameof(airlock_program.master_prog), src)


/datum/embedded_program/docking/airlock/receive_user_command(command)
	if (command == "toggle_override")
		if (override_enabled)
			disable_override()
		else
			enable_override()
		return TRUE

	. = ..(command)
	. = airlock_program.receive_user_command(command) || .	//pass along to subprograms; bypass shortcircuit

/datum/embedded_program/docking/airlock/periodic_step()
	airlock_program.periodic_step()
	..()

/datum/embedded_program/docking/airlock/receive_signal(datum/signal/signal, receive_method, receive_param)
	airlock_program.receive_signal(signal, receive_method, receive_param)	//pass along to subprograms
	..(signal, receive_method, receive_param)

//tell the docking port to start getting ready for docking - e.g. pressurize
/datum/embedded_program/docking/airlock/prepare_for_docking()
	airlock_program.begin_dock_cycle()

//are we ready for docking?
/datum/embedded_program/docking/airlock/ready_for_docking()
	return airlock_program.done_cycling()

//we are docked, open the doors or whatever.
/datum/embedded_program/docking/airlock/finish_docking()
	airlock_program.enable_mech_regulation()
	airlock_program.open_doors()

//tell the docking port to start getting ready for undocking - e.g. close those doors.
/datum/embedded_program/docking/airlock/prepare_for_undocking()
	airlock_program.stop_cycling()
	airlock_program.close_doors()
	airlock_program.disable_mech_regulation()

//are we ready for undocking?
/datum/embedded_program/docking/airlock/ready_for_undocking()
	var/ext_closed = airlock_program.check_exterior_door_secured()
	var/int_closed = airlock_program.check_interior_door_secured()
	return (ext_closed || int_closed)

///////////////////////////////////////////////////////////////////////////////
//An airlock controller to be used by the airlock-based docking port controller.
//Same as a regular airlock controller but allows disabling of the regular airlock functions when docking
//
/datum/embedded_program/airlock/docking
	var/datum/embedded_program/docking/airlock/master_prog

/datum/embedded_program/airlock/docking/relations()
	. = ..()
	. += rel_one(nameof(master_prog), back = nameof(/datum/embedded_program/docking/airlock::airlock_program))
/datum/embedded_program/docking/airlock/relations()
	. = ..()
	. += rel_one(nameof(airlock_program), back = nameof(/datum/embedded_program/airlock/docking::master_prog))

/datum/embedded_program/airlock/docking/receive_user_command(command)
	if (master_prog.undocked() || master_prog.override_enabled)	//only allow the port to be used as an airlock if nothing is docked here or the override is enabled
		return ..(command)

/datum/embedded_program/airlock/docking/proc/open_doors()
	toggleDoor(memory["interior_status"], tag_interior_door, memory["secure"], "open")
	toggleDoor(memory["exterior_status"], tag_exterior_door, memory["secure"], "open")

/datum/embedded_program/airlock/docking/cycleDoors(target)
	if (master_prog.undocked() || master_prog.override_enabled)	//only allow the port to be used as an airlock if nothing is docked here or the override is enabled
		..(target)

/// The running program (owns_one(starts =)): docking over the airlock program the map set.
/obj/machinery/embedded_controller/radio/airlock/docking_port/proc/make_docking_program(current)
	return new /datum/embedded_program/docking/airlock(src, airlock_program)
