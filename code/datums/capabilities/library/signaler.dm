// cap_signaler(): the holder is a remote signaling device of its own. It listens on its frequency
// through the radio service (as /obj/item/assembly/signaler does), sends an "ACTIVATE" signal with
// its code, and runs on_signal when a signal with its code arrives. "Set frequency" and "Set code"
// are forms; the tgui window gets `frequency`, `code`, `minFrequency` and `maxFrequency`.
//
// frequency = and code = are type defaults. A mapped or per-instance setting is the holder's own
// cap_signal_frequency / cap_signal_code var, read when set (design review H1).
//
//	/obj/item/remote_charge/capabilities()
//		. = ..()
//		. += cap_signaler(frequency = 1449, code = 12, on_signal = PROC_REF(detonate))

/obj
	/// Per-instance signaler frequency (the signaler capability); null: the type default.
	var/cap_signal_frequency
	/// Per-instance signaler code (the signaler capability); null: the type default.
	var/cap_signal_code

/// Time between two signals from one holder (the assembly signaler's activation cooldown).
#define SIGNALER_COOLDOWN (3 SECONDS)

/datum/capability/signaler
	data_type = /datum/cap_signaler_data
	log = LOG_GAME
	works_broken = FALSE
	works_unpowered = TRUE
	var/frequency = RSD_FREQ
	var/code = 30
	/// PROC_REF on the holder, (datum/signal/signal): runs when a signal with our code arrives.
	var/on_signal

/datum/cap_signaler_data
	/// world.time before which the holder can't signal again.
	var/next_signal = 0

/proc/cap_signaler(frequency = RSD_FREQ, code = 30, on_signal, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = FALSE, works_unpowered = TRUE, log = LOG_GAME)
	var/datum/capability/signaler/C = new
	C.frequency = sanitize_frequency(frequency, RADIO_LOW_FREQ, RADIO_HIGH_FREQ)
	C.code = clamp(round(code), 1, 100)
	C.on_signal = on_signal
	cap_gating(C, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered)
	return C

/datum/capability/signaler/interactions(atom/holder)
	var/datum/interaction/capability/send = adopt_entry(cap_hand("Send signal", TYPE_PROC_REF(/obj, cap_signaler_send), works_unpowered = TRUE))
	var/datum/interaction/capability/set_freq = adopt_entry(cap_hand("Set frequency", TYPE_PROC_REF(/obj, cap_signaler_set_frequency), works_unpowered = TRUE, form = list(number_field("frequency", min_value = RADIO_LOW_FREQ, max_value = RADIO_HIGH_FREQ, message = "Frequency, [RADIO_LOW_FREQ] to [RADIO_HIGH_FREQ] ([format_frequency(RSD_FREQ)] is [RSD_FREQ]):", title = "Signaler", default = frequency))))
	var/datum/interaction/capability/set_code = adopt_entry(cap_hand("Set code", TYPE_PROC_REF(/obj, cap_signaler_set_code), works_unpowered = TRUE, form = list(number_field("code", min_value = 1, max_value = 100, message = "Code, 1 to 100:", title = "Signaler", default = code))))
	for(var/datum/interaction/capability/E as anything in list(send, set_freq, set_code))
		E.default_action = null // Menu entries: an empty hand keeps doing the holder's own thing
	return list(send, set_freq, set_code)

/datum/capability/signaler/examine(atom/holder, mob/user)
	var/obj/O = holder
	return list("It is set to [format_frequency(cap_signaler_frequency(O))], code [cap_signaler_code(O)].")

/datum/capability/signaler/ui_data(atom/holder, mob/user, list/data)
	var/obj/O = holder
	data["frequency"] = cap_signaler_frequency(O)
	data["code"] = cap_signaler_code(O)
	data["minFrequency"] = RADIO_LOW_FREQ
	data["maxFrequency"] = RADIO_HIGH_FREQ

/datum/capability/signaler/on_holder_init(atom/holder, mapload)
	// Joins the radio on its frequency (moves to systems() once the core has it).
	var/obj/O = holder
	if(istype(O))
		GLOB.radio_service.add_object(O, cap_signaler_frequency(O), RADIO_CHAT)

/// The signaler capability of O, or null.
/proc/cap_signaler_cap(obj/O)
	return cap_of(O, /datum/capability/signaler)

/// O's frequency: its own cap_signal_frequency, else the type default.
/proc/cap_signaler_frequency(obj/O)
	if(!isnull(O.cap_signal_frequency))
		return O.cap_signal_frequency
	var/datum/capability/signaler/C = cap_signaler_cap(O)
	return C?.frequency

/// O's code: its own cap_signal_code, else the type default.
/proc/cap_signaler_code(obj/O)
	if(!isnull(O.cap_signal_code))
		return O.cap_signal_code
	var/datum/capability/signaler/C = cap_signaler_cap(O)
	return C?.code

/// Retunes O (sanitised to an odd frequency in the radio band) and moves its radio listener.
/proc/cap_signaler_tune(obj/O, frequency)
	var/old = cap_signaler_frequency(O)
	frequency = sanitize_frequency(frequency, RADIO_LOW_FREQ, RADIO_HIGH_FREQ)
	if(old == frequency)
		return frequency
	GLOB.radio_service.remove_object(O, old)
	O.cap_signal_frequency = frequency
	GLOB.radio_service.add_object(O, frequency, RADIO_CHAT)
	changed(O, CHANGE_CAPABILITY)
	return frequency

/// Sets O's code (1 to 100).
/proc/cap_signaler_set_code_to(obj/O, code)
	O.cap_signal_code = clamp(round(code), 1, 100)
	changed(O, CHANGE_CAPABILITY)
	return O.cap_signal_code

/// Sends O's signal. Null when it went out, else why not.
/proc/cap_signaler_signal(obj/O)
	var/datum/capability/signaler/C = cap_signaler_cap(O)
	var/datum/cap_signaler_data/D = cap_data(O, C)
	if(world.time < D.next_signal)
		return "it isn't ready yet"
	if(is_jammed(O))
		return "all you hear is static"
	var/datum/signal/signal = new
	rel_set(signal, nameof(signal.source), O)
	signal.encryption = cap_signaler_code(O)
	signal.data["message"] = "ACTIVATE"
	var/datum/radio_frequency/channel = GLOB.radio_service.return_frequency(cap_signaler_frequency(O))
	channel.post_signal(O, signal)
	D.next_signal = world.time + SIGNALER_COOLDOWN
	return null

/// A radio signal reached O (from /obj/receive_signal()): runs on_signal when the code matches.
/proc/cap_signaler_receive(obj/O, datum/signal/signal)
	var/datum/capability/signaler/C = cap_signaler_cap(O)
	if(!C || !signal || signal.encryption != cap_signaler_code(O) || is_jammed(O))
		return FALSE
	if(C.on_signal)
		call(O, C.on_signal)(signal)
	changed(O, CHANGE_CAPABILITY)
	return TRUE

/obj/proc/cap_signaler_send(mob/user)
	var/reason = cap_signaler_signal(src)
	if(reason)
		return refuse(user, "\The [src] doesn't signal: [reason].")
	to_chat(user, span_notice("You send a signal on [format_frequency(cap_signaler_frequency(src))], code [cap_signaler_code(src)]."))
	return TRUE

/obj/proc/cap_signaler_set_frequency(mob/user, frequency)
	frequency = ui_number(frequency, RADIO_LOW_FREQ, RADIO_HIGH_FREQ, 1)
	if(isnull(frequency))
		return refuse(user, "That isn't a frequency.")
	var/now = cap_signaler_tune(src, frequency)
	to_chat(user, span_notice("You tune \the [src] to [format_frequency(now)]."))
	return TRUE

/obj/proc/cap_signaler_set_code(mob/user, code)
	code = ui_number(code, 1, 100, 1)
	if(isnull(code))
		return refuse(user, "That isn't a code.")
	var/now = cap_signaler_set_code_to(src, code)
	to_chat(user, span_notice("You set \the [src]'s code to [now]."))
	return TRUE

#undef SIGNALER_COOLDOWN
