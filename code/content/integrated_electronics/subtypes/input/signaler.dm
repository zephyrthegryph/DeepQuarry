/obj/item/integrated_circuit/input/signaler
	name = "integrated signaler"
	desc = "Signals from a signaler can be received with this, allowing for remote control.  Additionally, it can send signals as well."
	extended_desc = "When a signal is received from another signaler, the 'on signal received' activator pin will be pulsed.  \
	The two input pins are to configure the integrated signaler's settings.  Note that the frequency should not have a decimal in it.  \
	Meaning the default frequency is expressed as 1457, not 145.7.  To send a signal, pulse the 'send signal' activator pin."
	icon_state = "signal"
	complexity = 4
	inputs = list("frequency" = IC_PINTYPE_NUMBER,"code" = IC_PINTYPE_NUMBER)
	outputs = list()
	activators = list(
		"send signal" = IC_PINTYPE_PULSE_IN,
		"on signal sent" = IC_PINTYPE_PULSE_OUT,
		"on signal received" = IC_PINTYPE_PULSE_OUT)
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	// power_draw_idle = 5 // Breaks recharging cells, and unnecessary for this circuit.
	power_draw_per_use = 40

	var/frequency = RSD_FREQ
	var/code = 30
	var/datum/radio_frequency/radio_connection

CAPABILITIES(/obj/item/integrated_circuit/input/signaler)
	setup(PROC_REF(configure_signaler_pins))
	ref_one(nameof(radio_connection), /datum/radio_frequency)
	after_init(4 SECONDS, then(PROC_REF(retune_after_init)))

/obj/item/integrated_circuit/input/signaler/proc/configure_signaler_pins()
	set_pin_data(IC_INPUT, 1, frequency)
	set_pin_data(IC_INPUT, 2, code)

/obj/item/integrated_circuit/input/signaler/on_data_written()
	var/new_freq = get_pin_data(IC_INPUT, 1)
	var/new_code = get_pin_data(IC_INPUT, 2)
	if(isnum(new_freq) && new_freq > 0)
		set_frequency(new_freq)
	if(isnum(new_code))
		code = num_or_null(new_code)

/obj/item/integrated_circuit/input/signaler/do_work() // Sends a signal.
	if(!radio_connection)
		return

	var/datum/signal/signal = new()
	rel_set(signal, nameof(signal.source), src)
	signal.encryption = code
	signal.data["message"] = "ACTIVATE"
	radio_connection.post_signal(src, signal)
	activate_pin(2)

/// Four seconds after init (after_init()): tunes to the frequency it was made with.
/obj/item/integrated_circuit/input/signaler/proc/retune_after_init(datum/act/A)
	set_frequency(frequency)

/obj/item/integrated_circuit/input/signaler/proc/set_frequency(new_frequency)
	if(!frequency)
		return
	if(!SSradio)
		return
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, RADIO_CHAT))

/obj/item/integrated_circuit/input/signaler/receive_signal(datum/signal/signal)
	var/new_code = get_pin_data(IC_INPUT, 2)
	var/code = 0

	if(isnum(new_code))
		code = new_code
	if(!signal)
		return 0
	if(signal.encryption != code)
		return 0
	if(signal.source() == src) // Don't trigger ourselves.
		return 0

	activate_pin(3)

	if(loc)
		for(var/mob/O in hearers(1, get_turf(src)))
			O.show_message("[icon2html(src, O.client)] *beep* *beep*", 3, "*beep* *beep*", 2)
