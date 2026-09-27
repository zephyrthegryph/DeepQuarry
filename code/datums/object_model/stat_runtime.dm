// Generic flat stat storage. Generated typed methods live in generated_stats.dm.
#define OM_STAT_ADD 1
#define OM_STAT_MULTIPLY 2
#define OM_STAT_MAX 3
#define OM_STAT_MIN 4
#define OM_STAT_FLAGS 5
#define OM_STAT_BASELINE 1
#define OM_STAT_RULE 2
#define OM_STAT_MINIMUM 3
#define OM_STAT_MAXIMUM 4

/datum/object_model/stat_block
	var/datum/owner
	var/change_mask = 1
	var/list/base_values
	var/list/effective_values
	var/list/sources // source datum -> sparse [id, value, id, value, ...]
	var/dirty = TRUE

/datum/object_model/stat_block/New(datum/new_owner)
	. = ..()
	owner = new_owner
	if(owner)
		if(QDELETED(owner))
			CRASH("cannot attach stat block to deleted owner")
		RegisterSignal(owner, COMSIG_QDELETING, PROC_REF(on_owner_deleting))

/datum/object_model/stat_block/proc/on_owner_deleting(datum/source)
	SIGNAL_HANDLER
	qdel(src)

/datum/object_model/stat_block/proc/on_source_deleting(datum/source)
	SIGNAL_HANDLER
	remove_source(source)

/datum/object_model/stat_block/Destroy()
	if(owner && !QDELETED(owner))
		UnregisterSignal(owner, COMSIG_QDELETING)
	if(sources)
		for(var/datum/source as anything in sources)
			if(source != owner && !QDELETED(source))
				UnregisterSignal(source, COMSIG_QDELETING)
	owner = null
	base_values = null
	effective_values = null
	sources = null
	return ..()

/// Generated domains return a proc-local static list indexed by compact stat ID.
/datum/object_model/stat_block/proc/definitions()
	CRASH("stat block [type] has no definitions")

/datum/object_model/stat_block/proc/get_stat(id)
	var/list/defs = definitions()
	if(id < 1 || id > length(defs))
		CRASH("invalid stat ID [id]")
	if(dirty)
		rebuild()
	return effective_values[id]

/datum/object_model/stat_block/proc/set_base_stat(id, value)
	var/list/defs = definitions()
	if(id < 1 || id > length(defs) || !isnum(value))
		CRASH("invalid stat write [id]=[value]")
	var/list/def = defs[id]
	if(!base_values)
		base_values = new/list(length(defs))
	var/old = base_values[id]
	var/baseline = def[OM_STAT_BASELINE]
	if((isnull(old) ? baseline : old) == value)
		return FALSE
	base_values[id] = value
	stat_changed()
	return TRUE

/// Replacement is atomic; callers may reuse a draft after this call.
/datum/object_model/stat_block/proc/set_source(datum/source, datum/object_model/stat_draft/draft)
	if(!source || QDELETED(source) || !draft || QDELETED(draft) || draft.block_type != type)
		CRASH("invalid stat source or draft for [type]")
	if(!sources)
		sources = list()
	var/list/replacement = draft.values.Copy()
	if(!length(replacement))
		return remove_source(source)
	var/list/previous = sources[source]
	if(om_stat_lists_equal(previous, replacement))
		return FALSE
	if(!(source in sources) && source != owner)
		RegisterSignal(source, COMSIG_QDELETING, PROC_REF(on_source_deleting))
	sources[source] = replacement
	stat_changed()
	return TRUE

/datum/object_model/stat_block/proc/remove_source(datum/source)
	if(!sources || !(source in sources))
		return FALSE
	sources -= source
	if(!length(sources))
		sources = null
	if(source != owner && !QDELETED(source))
		UnregisterSignal(source, COMSIG_QDELETING)
	stat_changed()
	return TRUE

/datum/object_model/stat_block/proc/stat_changed()
	dirty = TRUE
	if(owner && !QDELETED(owner))
		om_mark_changed(owner, change_mask)

/datum/object_model/stat_block/proc/rebuild()
	var/list/defs = definitions()
	var/list/result = new/list(length(defs))
	for(var/id in 1 to length(defs))
		var/list/def = defs[id]
		result[id] = base_values && !isnull(base_values[id]) ? base_values[id] : def[OM_STAT_BASELINE]
	if(sources)
		for(var/datum/source as anything in sources)
			var/list/contributions = sources[source]
			for(var/offset in 1 to length(contributions) step 2)
				var/id = contributions[offset]
				var/contribution = contributions[offset + 1]
				var/list/def = defs[id]
				switch(def[OM_STAT_RULE])
					if(OM_STAT_ADD)
						result[id] += contribution
					if(OM_STAT_MULTIPLY)
						result[id] *= contribution
					if(OM_STAT_MAX)
						result[id] = max(result[id], contribution)
					if(OM_STAT_MIN)
						result[id] = min(result[id], contribution)
					if(OM_STAT_FLAGS)
						result[id] |= contribution
	for(var/id in 1 to length(defs))
		var/list/def = defs[id]
		result[id] = clamp(result[id], def[OM_STAT_MINIMUM], def[OM_STAT_MAXIMUM])
	effective_values = result
	dirty = FALSE

/proc/om_stat_lists_equal(list/left, list/right)
	if(!left || !right || length(left) != length(right))
		return FALSE
	for(var/id in 1 to length(left))
		if(left[id] != right[id])
			return FALSE
	return TRUE

/datum/object_model/stat_draft
	var/block_type
	var/stat_count
	var/list/values

/datum/object_model/stat_draft/New(domain_type, count)
	. = ..()
	block_type = domain_type
	stat_count = count
	values = list()

/datum/object_model/stat_draft/proc/contribute(id, value, rule)
	if(id < 1 || id > stat_count || !isnum(value))
		CRASH("invalid stat contribution [id]=[value]")
	if(rule == OM_STAT_FLAGS && (value < 0 || value != round(value)))
		CRASH("flags stat contribution must be a nonnegative integer")
	for(var/offset in 1 to length(values) step 2)
		if(values[offset] != id)
			continue
		switch(rule)
			if(OM_STAT_ADD)
				values[offset + 1] += value
			if(OM_STAT_MULTIPLY)
				values[offset + 1] *= value
			if(OM_STAT_MAX)
				values[offset + 1] = max(values[offset + 1], value)
			if(OM_STAT_MIN)
				values[offset + 1] = min(values[offset + 1], value)
			if(OM_STAT_FLAGS)
				values[offset + 1] |= value
		return
	values += id
	values += value
