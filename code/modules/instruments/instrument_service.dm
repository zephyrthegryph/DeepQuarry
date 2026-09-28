// The instrument world service (fold wave F3; was SSinstruments): instrument data and instrument
// sound-channel bookkeeping. Playing songs run on the instruments continuous lane
// (PERIODIC_INSTRUMENTS, code/datums/om/periodic.dm) and every song is in REGISTRY_SONGS, so this
// has no periodic work: it is a lazy service, set up on first use through instrument_service().
GLOBAL_DATUM_INIT(instrument_service, /datum/world_service/instruments, new)

/// The instrument service, initialized on first use.
/proc/instrument_service() as /datum/world_service/instruments
	RETURN_TYPE(/datum/world_service/instruments)
	return LAZY_SERVICE(instrument_service)

/datum/world_service/instruments
	name = "Instruments"
	/// List of all instrument data, associative id = datum
	var/list/datum/instrument/instrument_data = list() // ALLOW(instance_list): d: world service singleton (one instance in GLOB, was a subsystem)
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
	var/list/note_sustain_modes = list( // ALLOW(instance_list): d: world service singleton (one instance in GLOB, was a subsystem)
		SUSTAIN_LINEAR,
		SUSTAIN_EXPONENTIAL,
	)

/datum/world_service/instruments/initialize()
	initialized = TRUE
	initialize_instrument_data()
	synthesizer_instrument_ids = get_allowed_instrument_ids()
	log_world("Instrument service initialized: [length(instrument_data)] instruments.")

/datum/world_service/instruments/stat_line()
	return "Songs: [REGISTRY_COUNT(REGISTRY_SONGS)] | Channels: [current_instrument_channels]/[max_instrument_channels]"

/datum/world_service/instruments/proc/initialize_instrument_data()
	for(var/path in subtypesof(/datum/instrument))
		var/datum/instrument/I = path
		if(initial(I.abstract_type) == path)
			continue
		I = new path
		I.Initialize()
		if(!I.id)
			qdel(I)
			continue
		instrument_data[I.id] = I

/datum/world_service/instruments/proc/get_instrument(id_or_path)
	return instrument_data["[id_or_path]"]

/datum/world_service/instruments/proc/reserve_instrument_channel(datum/instrument/I)
	if(current_instrument_channels > max_instrument_channels)
		return
	. = sound_service().reserve_sound_channel(I)
	if(!isnull(.))
		current_instrument_channels++

REF_OWNED_VALUES(/datum/world_service/instruments, list("instrument_data"))
