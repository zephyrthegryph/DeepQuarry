//Basically a one way passive valve. If the pressure inside is greater than the environment then gas will flow passively,
//but it does not permit gas to flow back from the environment into the injector. Can be turned off to prevent any gas flow.
//When it receives the "inject" signal, it will try to pump it's entire contents into the environment regardless of pressure, using power.

/obj/machinery/atmospherics/unary/outlet_injector
	icon = 'icons/atmos/injector.dmi'
	icon_state = "map_injector"
	pipe_state = "injector"

	name = "air injector"
	desc = "Passively injects air into its surroundings. Has a valve attached to it that can control flow rate."

	use_power = USE_POWER_OFF
	idle_power_usage = 150		//internal circuitry, friction losses and stuff
	power_rating = 15000	//15000 W ~ 20 HP

	var/injecting = 0

	var/volume_rate = 50	//flow rate limit

	var/frequency = ZERO_FREQ
	var/id = null
	var/datum/radio_frequency/radio_connection

	level = 1

/obj/machinery/atmospherics/unary/outlet_injector/Initialize(mapload)
	. = ..()

	air_contents.set_volume(ATMOS_DEFAULT_VOLUME_PUMP + 500)	//Give it a small reservoir for injecting. Also allows it to have a higher flow rate limit than vent pumps, to differentiate injectors a bit more.
	if(frequency)
		set_frequency(frequency)

/obj/machinery/atmospherics/unary/outlet_injector/draw(datum/look/look)
	..()
	look.state((operable() && use_power) ? "on" : "off")

/obj/machinery/atmospherics/unary/outlet_injector/update_underlays()
	..()
	underlays.Cut()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	add_underlay(T, node, dir)

// ---- the Rust device edge ----

/// The injector's flow (device.rs Flow): `volume_rate` litres a second of its pipe's gas, forced into the turf it stands on (side A) whatever the
/// room holds. Pushed once per frame after anything it reads changed.
/obj/machinery/atmospherics/unary/outlet_injector/push_to_rust()
	if(QDELETED(src))
		return
	var/datum/gas_mixture/environment = return_air()
	if(!node || !operable() || !use_power || !environment) // ALLOW(derived_reads): a port bind, a disconnect and a power change bump rust_device_rev
		rust_unregister_device()
		return
	rust_set_turf_device(1, environment)
	rust_set_device_flow(0, RUST_FLOW_VOLUME, volume_rate, RUST_DIR_FORCED, RUST_SIDE_A, RUST_STOP_AT_LEAST, 1e30)

/obj/machinery/atmospherics/unary/outlet_injector/rust_device_stepped(moles, power_w, target_reached)
	last_flow_rate = abs(moles)

/// The Rust law is pushed (once per frame) when any of these change: rust_device_rev is bumped by a power change, a port bind and a disconnect.
/obj/machinery/atmospherics/unary/outlet_injector/derived()
	. = ..()
	. += rust_push(nameof(rust_device_rev), nameof(volume_rate))
	. += drawn_from(nameof(use_power))

/obj/machinery/atmospherics/unary/outlet_injector/proc/inject()
	if(injecting || (power_lost()))
		return 0

	var/datum/gas_mixture/environment = loc.return_air()
	if (!environment)
		return 0

	injecting = 1

	if(air_contents.return_temperature() > 0)
		var/power_used = pump_gas(src, air_contents, environment, air_contents.total_moles(), power_rating)
		use_power(power_used)
		// same enroll-turf reason as in process().
		if(isturf(loc))
			var/turf/open/T = loc
			if(istype(T))
				T.update_visuals()
				T.air_update_turf(FALSE, FALSE)

		gas_touched(air_contents)

	flick("inject", src)

/obj/machinery/atmospherics/unary/outlet_injector/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency))

/obj/machinery/atmospherics/unary/outlet_injector/proc/broadcast_status()
	if(!radio_connection)
		return 0

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	rel_set(signal, nameof(signal.source), src)

	signal.data = list(
		"tag" = id,
		"device" = "AO",
		"power" = use_power,
		"volume_rate" = volume_rate,
		"sigtype" = "status"
	)

	radio_connection.post_signal(src, signal)

	return 1

/obj/machinery/atmospherics/unary/outlet_injector/receive_signal(datum/signal/signal)
	if(!signal.data["tag"] || (signal.data["tag"] != id) || (signal.data["sigtype"]!="command"))
		return 0

	if(signal.data["power"])
		set_use_power(text2num(signal.data["power"]))

	if(signal.data["power_toggle"])
		set_use_power(!use_power)

	if(signal.data["inject"])
		inject()
		return

	if(signal.data["set_volume_rate"])
		var/number = text2num(signal.data["set_volume_rate"])
		set_volume_rate(between(0, number, air_contents.return_volume()))

	if(signal.data["status"])
		after(src, 0.2 SECONDS, PROC_REF(broadcast_status))
		return //do not update_icon

	after(src, 0.2 SECONDS, PROC_REF(broadcast_status))

/obj/machinery/atmospherics/unary/outlet_injector/hide(i)
	update_underlays()

TRACKED(/obj/machinery/atmospherics/unary/outlet_injector, volume_rate)
TRACKED(/obj/machinery/atmospherics/unary/outlet_injector, id)

MSG_DEF_SELF(outlet_injector/toggled, "You toggle the injector.")
MSG_DEF_SELF(outlet_injector/rate_reset, "You set the injector back to its default rate.")

CAPABILITIES(/obj/machinery/atmospherics/unary/outlet_injector)
	// The unary base's ctrl-click power_toggle is never offered on an injector (ctrl_power_offered()); its ctrl-click is
	// reset_rate. The static clash check cannot see the when(), and reported the two at boot.
	without("power_toggle")
	op("toggle", hand(), label("Toggle"), wait(0), says(MSG(outlet_injector/toggled)), then(PROC_REF(toggled)))
	op("reset_rate", hand(), gesture(GESTURE_CTRL), label("Reset the rate"), wait(0), when(PROC_REF(rate_resettable)), says(MSG(outlet_injector/rate_reset)),
		then(PROC_REF(rate_reset)))
	multitool_settings(list(
		list("ID Tag", "id", "text", MAX_NAME_LEN),
		list("Frequency", "frequency", "frequency"),
		list("-SAVE TO BUFFER-", PROC_REF(save_to_buffer), "action")))
	pipe_device_unwrench()

/// The injector comes off its pipe whether it runs or not (only its gas holds it).
/obj/machinery/atmospherics/unary/outlet_injector/pipe_device_idle(datum/act/A)
	return TRUE

/obj/machinery/atmospherics/unary/outlet_injector/proc/toggled(datum/act/op/A)
	injecting = !injecting
	set_use_power(injecting ? USE_POWER_IDLE : USE_POWER_OFF)
	return OP_OK

/// A running injector away from its default rate.
/obj/machinery/atmospherics/unary/outlet_injector/proc/rate_resettable(datum/act/op/A)
	return use_power && volume_rate != ATMOS_DEFAULT_VOLUME_PUMP + 500

/obj/machinery/atmospherics/unary/outlet_injector/proc/rate_reset(datum/act/op/A)
	set_volume_rate(ATMOS_DEFAULT_VOLUME_PUMP + 500)
	return OP_OK

/// The multitool's "-SAVE TO BUFFER-": the injector goes into the multitool's buffer (for linking).
/obj/machinery/atmospherics/unary/outlet_injector/proc/save_to_buffer(datum/act/op/A)
	var/obj/item/multitool/tool = A.held
	if(istype(tool))
		rel_set(tool, nameof(tool.connectable), src)
		to_chat(A.actor, span_notice("You copied the [src] into the [tool]'s buffer!"))

