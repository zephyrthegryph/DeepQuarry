// The instrument system's API (code/modules/instruments/instrument_service.dm declares the system).
//
//   SSinstruments.ready()                                    the system, initialized (it is lazy)
//   SSinstruments.get_instrument(id_or_path)                 one instrument datum
//   SSinstruments.reserve_instrument_channel(instrument)     a sound channel for a song, or null when the channels are used up

/datum/system/instruments/proc/get_instrument(id_or_path)
	return instrument_data["[id_or_path]"]

/datum/system/instruments/proc/reserve_instrument_channel(datum/instrument/I)
	if(current_instrument_channels > max_instrument_channels)
		return
	. = SSsounds.ready().reserve_sound_channel(I)
	if(!isnull(.))
		current_instrument_channels++
