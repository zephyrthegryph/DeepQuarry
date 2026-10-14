// A pipe device's own controls (doc/rewrite/final_api.html section 9): what every device on the pipe network shares, a pump, a regulator, a valve,
// a filter or a mixer, a connector, an injector. Each is a plain proc returning entries, declared in the device's CAPABILITIES block:
//
//   pipe_device_unwrench()          the wrench takes it off its pipes into its fitting: refused while it runs (pipe_device_idle()) and while its
//                                    gas pushes back (can_unwrench()). A device that runs by something else than its power switch overrides
//                                    pipe_device_idle() (a regulator: its valve).
//   pipe_device_window(window)      its window, opened by a hand for someone its access lets in while it works.
//   pipe_device_switch()            the ctrl-click power switch, for someone its access lets in (toggle_power() is what it does).
//   pipe_device_max(proc)           the alt-click that sets its highest output, for someone its access lets in.
//
// Example (the pressure pump):
//
//	CAPABILITIES(/obj/machinery/atmospherics/binary/pump)
//		pipe_device_window("GasPump")
//		pipe_device_switch()
//		pipe_device_max(PROC_REF(max_output_set))
//		pipe_device_unwrench()

MSG_DEF_SELF(pipe_device/running, "You cannot unwrench it, turn it off first.")
MSG_DEF_SELF(pipe_device/exerted, "You cannot unwrench it, it is too exerted due to internal pressure.")
MSG_DEF(pipe_device/unfastened, "You have unfastened %T%.", "%U% unfastens %T%.")
MSG_DEF_SELF(pipe_device/toggled_on, "You switch it on.")
MSG_DEF_SELF(pipe_device/toggled_off, "You switch it off.")
MSG_DEF_SELF(pipe_device/maxed, "You set it to its highest output.")

/// The wrench that takes a pipe device off its pipes into its fitting.
/proc/pipe_device_unwrench()
	return list(op("unwrench", tool(TOOL_WRENCH), wait(4 SECONDS),
		needs(req(TYPE_PROC_REF(/obj/machinery/atmospherics, pipe_device_idle)),
			req(TYPE_PROC_REF(/obj/machinery/atmospherics, unwrench_safe))),
		says(MSG(pipe_device/unfastened)),
		then(TYPE_PROC_REF(/obj/machinery/atmospherics, unfastened))))

/// The device's window: a hand opens it for someone its access lets in, while it works.
/proc/pipe_device_window(window)
	return list(interface(window),
		extend("ui_open", needs(req(TYPE_PROC_REF(/obj/machinery/atmospherics, device_works)),
			req(TYPE_PROC_REF(/obj/machinery/atmospherics, actor_allowed)))))

/// The ctrl-click power switch.
/proc/pipe_device_switch()
	return list(op("power_toggle", hand(), gesture(GESTURE_CTRL), label("Toggle power"), wait(0),
		needs(req(TYPE_PROC_REF(/obj/machinery/atmospherics, actor_allowed))),
		says(TYPE_PROC_REF(/obj/machinery/atmospherics, toggled_message)),
		then(TYPE_PROC_REF(/obj/machinery/atmospherics, ctrl_power_toggled))))

/// The alt-click that sets the device to its highest output (`max_proc`, a holder proc: x(datum/act/op/A)).
/proc/pipe_device_max(max_proc)
	return list(op("max_output", hand(), gesture(GESTURE_ALT), label("Set to max output"), wait(0),
		needs(req(TYPE_PROC_REF(/obj/machinery/atmospherics, actor_allowed))),
		says(MSG(pipe_device/maxed)), then(max_proc)))

// ---- what the controls ask of the device ----

/// It is not running: unpowered, or switched off. A device whose running is something else (a regulator's open valve) says so here.
/obj/machinery/atmospherics/proc/pipe_device_idle(datum/act/A)
	return (power_lost() || !use_power) ? null : MSG(pipe_device/running)

/// Its gas lets it come off its pipes (can_unwrench(): the inside not too far above the room).
/obj/machinery/atmospherics/proc/unwrench_safe(datum/act/A)
	return (can_unwrench()) ? null : MSG(pipe_device/exerted)

/// It works (operable(): the machine core's stat bits, read when the window opens).
/obj/machinery/atmospherics/proc/device_works(datum/act/A)
	return (operable()) ? null : MSG(machine/inoperable)

/// The actor's access lets them work it.
/obj/machinery/atmospherics/proc/actor_allowed(datum/act/op/A)
	return (allowed(A.actor)) ? null : MSG(lock/denied)

/// The wrench took it off: it becomes its fitting.
/obj/machinery/atmospherics/proc/unfastened(datum/act/op/A)
	atom_deconstruct()
	return OP_OK

/// The power switch: the device runs or stops. A device with more to its switch (a pump's Rust-owned on flag) extends toggle_power().
/obj/machinery/atmospherics/proc/ctrl_power_toggled(datum/act/op/A)
	var/mob/user = A.actor
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	toggle_power()
	return OP_OK

/// What the switch says: what it did (asked once it is done).
/obj/machinery/atmospherics/proc/toggled_message(datum/act/A)
	return use_power ? /datum/msg/pipe_device/toggled_on : /datum/msg/pipe_device/toggled_off

/// Runs it, or stops it.
/obj/machinery/atmospherics/proc/toggle_power()
	set_use_power(!use_power)
