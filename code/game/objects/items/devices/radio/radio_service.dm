/*
	HOW IT WORKS

	The radio service (SSradio) is a global object maintaining all radio transmissions, think about it as about "ether".
	Note that walkie-talkie, intercoms and headsets handle transmission using nonstandard way.
	procs:

		add_object(obj/device as obj, var/new_frequency as num, var/radio_filter as text|null = null)
		Adds listening object.
		parameters:
			device - device receiving signals, must have proc receive_signal (see description below).
			one device may listen several frequencies, but not same frequency twice.
			new_frequency - see possibly frequencies below;
			radio_filter - thing for optimization. Optional, but recommended.
				All filters should be consolidated in this file, see defines later.
				Device without listening filter will receive all signals (on specified frequency).
				Device with filter will receive any signals sent without filter.
				Device with filter will not receive any signals sent with different filter.
		returns:
		Reference to frequency object.

	remove_object (obj/device, old_frequency)
		Obliviously, after calling this proc, device will not receive any signals on old_frequency.
		Other frequencies will left unaffected.

	return_frequency(var/frequency as num)
		returns:
		Reference to frequency object. Use it if you need to send and do not need to listen.

	radio_frequency is a global object maintaining list of devices that listening specific frequency.
	procs:

	post_signal(obj/source as obj|null, datum/signal/signal, var/radio_filter as text|null = null, var/range as num|null = null)
		Sends signal to all devices that wants such signal.
		parameters:
			source - object, emitted signal. Usually, devices will not receive their own signals.
			signal - see description below.
			radio_filter - described above.
			range - radius of regular byond's square circle on that z-level. null means everywhere, on all z-levels.

	obj/proc/receive_signal(datum/signal/signal, var/receive_method as num, var/receive_param)
		Handler from received signals. By default does nothing. Define your own for your object.
		Avoid sending signals directly from this proc: defer them with after(). Never block here; take time with an op wait() or after().
		parameters:
			signal - see description below. Extract all needed data from the signal before deferring work or returning!
			receive_method - may be TRANSMISSION_WIRE or TRANSMISSION_RADIO.
			TRANSMISSION_WIRE is currently unused.
			receive_param - for TRANSMISSION_RADIO here comes frequency.

	datum/signal
		vars:
		source
		an object that emitted signal. Used for debug and bearing.
		data
		list with transmitting data. Usual use pattern:
			data["msg"] = "hello world"
		encryption
		Some number symbolizing "encryption key".
		Note that game actually do not use any cryptography here.
		If receiving object don't know right key, it must ignore encrypted signal in its receive_signal.

*/

// The radio system (was SSradio). Data only: devices join frequencies as they initialize; it boots after
// SSatoms (the global announcer). The API is in radio_api.dm.
SYSTEM_DEF(radio)
	name = "Radio"
	needs = list(/datum/system/atoms)
	var/list/datum/radio_frequency/frequencies = list()

CAPABILITIES(/datum/system/radio)
	owns_many(nameof(frequencies), /datum/radio_frequency)

/// The system owns its frequencies (keyed by frequency text).

/datum/system/radio/initialize()
	if(initialized)
		return
	initialized = TRUE
	GLOB.autospeaker = new (null, FALSE, null, null, TRUE) //Set up Global Announcer
	log_world("System [name] initialized: [length(frequencies)] frequencies in use.")

//Frequency channels

/datum/radio_frequency
	var/frequency as num
	var/list/list/obj/devices = list() // ALLOW(instance_list): d: frequencies exist because devices joined them

/datum/radio_frequency/proc/post_signal(obj/source as obj|null, datum/signal/signal, radio_filter = null as text|null, range = null as num|null)
	CHURN_COUNT(signals, "[frequency] [source?.type]")
	var/turf/start_point
	if(range)
		start_point = get_turf(source)
		if(!start_point)
			spent(signal)
			return 0
	if (radio_filter)
		send_to_filter(source, signal, radio_filter, start_point, range)
		send_to_filter(source, signal, RADIO_DEFAULT, start_point, range)
	else
		//Broadcast the signal to everyone!
		for (var/next_filter in devices)
			send_to_filter(source, signal, next_filter, start_point, range)

//Sends a signal to all machines belonging to a given filter. Should be called by post_signal()
/datum/radio_frequency/proc/send_to_filter(obj/source, datum/signal/signal, radio_filter, turf/start_point = null, range = null)
	if (range && !start_point)
		return

	for(var/obj/device in devices[radio_filter])
		if(device == source)
			continue
		if(range)
			var/turf/end_point = get_turf(device)
			if(!end_point)
				continue
			if(start_point.z!=end_point.z || get_dist(start_point, end_point) > range)
				continue

		device.receive_signal(signal, TRANSMISSION_RADIO, frequency)

/datum/radio_frequency/proc/add_listener(obj/device as obj, radio_filter as text|null)
	if (!radio_filter)
		radio_filter = RADIO_DEFAULT
	var/list/obj/devices_line = devices[radio_filter]
	if (!devices_line)
		devices_line = new
		devices[radio_filter] = devices_line
	devices_line |= device // idempotent: on_materialize() may rejoin what Initialize() already joined
	// The frequency owns the membership: a listener that is destroyed leaves by
	// itself, so no device unregisters its radio in Destroy().
	observe(device, /datum/notice/qdeleting, src, then(PROC_REF(on_listener_deleted)))

/datum/radio_frequency/proc/on_listener_deleted(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/obj/device = A.target
	SSradio.remove_object(device, frequency)

/datum/radio_frequency/proc/remove_listener(obj/device)
	unobserve(device, /datum/notice/qdeleting, src)
	for (var/devices_filter in devices)
		var/list/devices_line = devices[devices_filter]
		devices_line-=device
		while (null in devices_line)
			devices_line -= null
		if (!length(devices_line))
			devices -= devices_filter

/datum/signal
	var/obj/source

	var/transmission_method = 0 //unused at the moment
	//0 = wire
	//1 = radio transmission
	//2 = subspace transmission

	var/list/data = list() // ALLOW(instance_list): d: every signal carries data
	var/encryption

	var/frequency = ZERO_FREQ

/datum/signal/proc/copy_from(datum/signal/model)
	rel_set(src, nameof(source), model.source)
	transmission_method = model.transmission_method
	data = model.data
	encryption = model.encryption
	frequency = model.frequency

/datum/signal/proc/debug_print()
	var/obj/sender = source()
	if (sender)
		. = "signal = {source = '[sender]' ([sender.x],[sender.y],[sender.z])\n"
	else
		. = "signal = {source = '[sender]' ()\n"
	for (var/i in data)
		. += "data\[\"[i]\"\] = \"[data[i]]\"\n"
		if(islist(data[i]))
			var/list/L = data[i]
			for(var/t in L)
				. += "data\[\"[i]\"\] list has: [t]"

//callback used by objects to react to incoming radio signals
/obj/proc/receive_signal(datum/signal/signal, receive_method, receive_param)
	cap_signaler_receive(src, signal) // a holder of the signaler capability (capabilities/library/signaler.dm)
	return null

/// Relation view: the device that sent this signal (reads null once it is gone).
/datum/signal/proc/source() as /obj
	return source
