#define TELECOMMS_RECEPTION_NONE 0
#define TELECOMMS_RECEPTION_SENDER 1
#define TELECOMMS_RECEPTION_RECEIVER 2
#define TELECOMMS_RECEPTION_BOTH 3

/proc/register_radio(source, old_frequency, new_frequency, radio_filter)
	if(old_frequency)
		GLOB.radio_service.remove_object(source, old_frequency)
	if(new_frequency)
		return GLOB.radio_service.add_object(source, new_frequency, radio_filter)

/proc/unregister_radio(source, frequency)
	if(GLOB.radio_service)
		GLOB.radio_service.remove_object(source, frequency)

/proc/get_frequency_name(display_freq)
	var/freq_text

	// the name of the channel
	if(display_freq in GLOB.antag_frequencies)
		freq_text = "#unkn"
	else
		for(var/channel in GLOB.radiochannels)
			if(GLOB.radiochannels[channel] == display_freq)
				freq_text = channel
				break

	// --- If the frequency has not been assigned a name, just use the frequency as the name ---
	if(!freq_text)
		freq_text = format_frequency(display_freq)

	return freq_text

#undef TELECOMMS_RECEPTION_NONE
#undef TELECOMMS_RECEPTION_SENDER
#undef TELECOMMS_RECEPTION_RECEIVER
#undef TELECOMMS_RECEPTION_BOTH
