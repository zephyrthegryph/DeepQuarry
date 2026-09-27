// Internal derived-value cache. Public declarations can supply the keys and
// dependency channels without allocating metadata on untouched datums.
#define OM_CACHE_DEFAULT "default"
#define OM_CACHE_ENTRY_VALUE 1
#define OM_CACHE_ENTRY_GLOBAL 2
#define OM_CACHE_ENTRY_CHANNELS 3
#define OM_CACHE_ENTRY_REVISIONS 4

/proc/om_cache_field_channel(field)
	return "field:[field]"

/// Call immediately after changing a scalar read by a declared cache.
/proc/om_field_changed(datum/subject, field)
	if(!istext(field) || !length(field))
		CRASH("invalid derived cache field [field]")
	om_changed(subject, om_cache_field_channel(field))

/datum/object_model/cache_state
	var/list/revisions
	var/global_revision = 0
	var/list/entries
	var/list/computing

/datum/proc/om_compute_cached(key)
	CRASH("[type] has no derived cache computation for [key]")

/// Override with proc-local static lists so hot reads allocate no list.
/datum/proc/om_cache_channels(key)
	var/static/list/default_channels = list(OM_CACHE_DEFAULT)
	return default_channels

/// Null is cached. Concurrent writes retry; same-key recursive reads crash.
/datum/proc/om_cached(key, list/channels)
	if(QDELETED(src) || isnull(key))
		return null
	var/datum/object_model/archetype/A = om_archetype_for(type, src)
	var/list/cache_def = A?.caches?[key]
	if(!channels)
		channels = cache_def ? cache_def["channels"] : om_cache_channels(key)
	var/datum/object_model/state/model_state = om_state_for(src)
	var/datum/object_model/cache_state/state = model_state.cache
	if(!state)
		state = new
		model_state.cache = state
	if(!state.revisions)
		state.revisions = list()
	if(!state.entries)
		state.entries = list()
	var/list/entry = state.entries[key]
	if(entry && om_cache_entry_current(state, entry, channels))
		return entry[OM_CACHE_ENTRY_VALUE]
	if(state.computing?[key])
		CRASH("reentrant derived cache read: [type] [key]")
	if(!state.computing)
		state.computing = list()
	state.computing[key] = TRUE
	for(var/attempt in 1 to 3)
		var/global_before = state.global_revision
		var/list/before = list()
		for(var/channel in channels)
			before[channel] = state.revisions[channel] || 0
		var/value
		if(cache_def)
			if(!hascall(src, key))
				CRASH("[type] has no declared cache compute proc [key]")
			value = call(src, key)()
		else
			value = om_compute_cached(key)
		if(QDELETED(src) || model_state.cache != state)
			state.computing -= key
			return null
		if(global_before != state.global_revision)
			continue
		var/stable = TRUE
		for(var/channel in channels)
			if(before[channel] != (state.revisions[channel] || 0))
				stable = FALSE
				break
		if(!stable)
			continue
		entry = list(value, global_before, channels, before)
		state.entries[key] = entry
		state.computing -= key
		return value
	state.computing -= key
	CRASH("derived cache changed repeatedly during computation: [type] [key]")

/proc/om_cache_entry_current(datum/object_model/cache_state/state, list/entry, list/channels)
	var/list/entry_channels = entry[OM_CACHE_ENTRY_CHANNELS]
	var/list/entry_revisions = entry[OM_CACHE_ENTRY_REVISIONS]
	if(entry[OM_CACHE_ENTRY_GLOBAL] != state.global_revision || length(entry_channels) != length(channels))
		return FALSE
	for(var/channel in channels)
		if(!(channel in entry_channels) || entry_revisions[channel] != (state.revisions[channel] || 0))
			return FALSE
	return TRUE

/// Null invalidates all entries on the subject.
/datum/proc/om_cache_changed(channel = null)
	var/datum/object_model/cache_state/state = om_state?.cache
	if(!state)
		return
	if(isnull(channel))
		state.global_revision++
	else
		if(!state.revisions)
			state.revisions = list()
		state.revisions[channel] = (state.revisions[channel] || 0) + 1
	if(state.global_revision >= 1000000 || (!isnull(channel) && state.revisions[channel] >= 1000000))
		state.global_revision = 0
		state.revisions = null
		state.entries = null

/proc/om_cache_clear(datum/subject)
	var/datum/object_model/cache_state/state = subject?.om_state?.cache
	if(!state)
		return
	state.entries = null
	state.revisions = null
	state.computing = null
	subject.om_state.cache = null
