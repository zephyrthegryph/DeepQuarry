// The instrument system (was SSinstruments): instrument data and instrument sound-channel bookkeeping.
// Playing songs schedule their own notes and
// every song is in REGISTRY_SONGS, so this has no periodic work: it is a lazy system, set up on first use
// through SSinstruments.ready() (it stays out of the boot DAG).
SYSTEM_DEF(instruments)
	name = "Instruments"
	/// List of all instrument data, associative id = datum
	var/list/datum/instrument/instrument_data = list()
	/// Max lines in songs
	var/musician_maxlines = 600
	/// Max characters per line in songs
	var/musician_maxlinechars = 300
	/// Deciseconds between hearchecks. Too high and instruments seem to lag when people are moving around in terms of who can hear it. Too low and the server lags from this.
	var/musician_hearcheck_mindelay = 5
	/// Maximum instrument channels total instruments are allowed to use. This is so you don't have instruments deadlocking all sound channels.
	var/max_instrument_channels = MAX_INSTRUMENT_CHANNELS
	/// Current number of channels allocated for instruments
	var/current_instrument_channels = 0
	/// Single cached list for synthesizer instrument ids, so you don't have to have a new list with every synthesizer.
	var/list/synthesizer_instrument_ids
	var/list/note_sustain_modes = list(
		SUSTAIN_LINEAR,
		SUSTAIN_EXPONENTIAL,
	)

/datum/system/instruments/boots_in_dag()
	return FALSE

/// Typed, so `SSinstruments.ready().var` reads as the system's own var.
/datum/system/instruments/ready()
	RETURN_TYPE(/datum/system/instruments)
	return ..()

/datum/system/instruments/initialize()
	initialized = TRUE
	initialize_instrument_data()
	synthesizer_instrument_ids = get_allowed_instrument_ids()
	log_world("Instrument service initialized: [length(instrument_data)] instruments.")

/datum/system/instruments/stat_entry(msg)
	return "[..()]Songs: [REGISTRY_COUNT(REGISTRY_SONGS)] | Channels: [current_instrument_channels]/[max_instrument_channels]"

/datum/system/instruments/proc/initialize_instrument_data()
	for(var/path in subtypesof(/datum/instrument))
		var/datum/instrument/I = path
		if(initial(I.abstract_type) == path)
			continue
		I = new path
		I.Initialize()
		if(!I.id)
			spent(I)
			continue
		instrument_data[I.id] = I
