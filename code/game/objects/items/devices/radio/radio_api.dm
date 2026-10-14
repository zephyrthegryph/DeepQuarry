// The radio system's API (code/game/objects/items/devices/radio/radio_service.dm declares the system).
//
//   SSradio.add_object(device, frequency, radio_filter)   join a device to a frequency; answers the frequency datum
//   SSradio.remove_object(device, old_frequency)           take a device off a frequency
//   SSradio.return_frequency(frequency)                    the frequency datum (made when missing)

/datum/system/radio/proc/add_object(obj/device as obj, new_frequency as num, radio_filter = null as text|null)
	var/f_text = num2text(new_frequency)
	var/datum/radio_frequency/frequency = frequencies[f_text]

	if(!frequency)
		frequency = new
		frequency.frequency = new_frequency
		rel_add(src, nameof(frequencies), frequency, f_text)

	frequency.add_listener(device, radio_filter)
	return frequency

/datum/system/radio/proc/remove_object(obj/device, old_frequency)
	var/f_text = num2text(old_frequency)
	var/datum/radio_frequency/frequency = frequencies[f_text]

	if(frequency)
		frequency.remove_listener(device)

		if(!length(frequency.devices))
			rel_add(src, nameof(frequencies), null, f_text) // disposes of (deletes) the emptied frequency

	return 1

/datum/system/radio/proc/return_frequency(new_frequency as num)
	var/f_text = num2text(new_frequency)
	var/datum/radio_frequency/frequency = frequencies[f_text]

	if(!frequency)
		frequency = new
		frequency.frequency = new_frequency
		rel_add(src, nameof(frequencies), frequency, f_text)

	return frequency
