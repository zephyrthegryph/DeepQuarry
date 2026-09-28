// Declared fields (doc/rewrite/object_model_core.md §5.1).
//
// A var that a stage, behaviour or watch reads to decide whether it has work is a declared
// field: a decl lists it with the channel its change raises,
//
//	/datum/om/decl/portable_pump_fields
//		of = /obj/machinery/portable_atmospherics/powered/pump
//		fields = list("on" = CHANGE_MACHINE_SETTINGS)
//
// and every write goes through the core: om_set(E, "on", TRUE), or the typed setter
// OM_SETTER(type, on) generates (E.set_on(TRUE)). Both raise the declared channel, and only
// when the value changed. A stage names what it reads (`reads = list("on")`); the registry
// checks at boot that its wake_on covers the channel of every field it reads, and
// tools/ci/api_lints.py (field_write) bans direct writes to a declared field outside its
// setter and Initialize()/New(). Together: nothing a stage reads can change without waking it.

/datum/om/registry
	/// type path -> field name -> channel (every decl whose `of` is an ancestor, merged).
	var/list/fields_by_type = list() // ALLOW(instance_list): d: registry singleton, filled per entity type on first use

/// Declared fields of `path` (and its ancestors): field name -> channel.
/datum/om/registry/proc/fields_of(path)
	RETURN_TYPE(/list)
	var/list/F = fields_by_type[path]
	if(F)
		return F
	F = list()
	for(var/datum/om/decl/D as anything in decls)
		var/applies = FALSE
		for(var/of_path in (islist(D.of) ? D.of : list(D.of)))
			if(ispath(path, of_path))
				applies = TRUE
				break
		if(!applies)
			continue
		for(var/datum/om/bundle/B as anything in expand(D.type, list()))
			for(var/name in B.fields)
				F[name] |= B.fields[name]
	fields_by_type[path] = F
	return F

/// Boot check: every stage (and behaviour) that `reads` a field is woken by its channel.
/// Returns the problems (also recorded as registry errors).
/datum/om/registry/proc/check_field_reads()
	. = list()
	for(var/path in stage_by_type)
		var/datum/om/stage/T = stage_by_type[path]
		if(!length(T.reads))
			continue
		var/mask = T.wake_mask || T.wake_on
		var/list/F = fields_of(T.of)
		for(var/name in T.reads)
			var/channel = F[name]
			if(!channel)
				. += "[T.type] reads [name], which [T.of] does not declare as a field"
			else if(!(mask & channel))
				. += "[T.type] reads [name] (channel [channel]) but its wake_on [mask] does not cover it"
	for(var/datum/om/behaviour/B as anything in behaviours)
		if(!length(B.reads))
			continue
		if(!B.reads_of)
			. += "[B.type] reads fields but names no reads_of type"
			continue
		var/list/F = fields_of(B.reads_of)
		for(var/name in B.reads)
			var/channel = F[name]
			if(!channel)
				. += "[B.type] reads [name], which [B.reads_of] does not declare as a field"
			else if(!(B.wake_on & channel))
				. += "[B.type] reads [name] (channel [channel]) but its wake_on [B.wake_on] does not cover it"
	for(var/problem in .)
		error(problem)

/// The channel declared for `E`'s field `name`, or 0.
/proc/om_field_channel(datum/E, name) // ALLOW(base_proc): global API written before the base-type ratchet
	var/list/F = om_registry().fields_of(E.type)
	return F[name] || 0

/// The one write path for a declared field: sets `E.name` to `value` and raises the field's
/// declared channel. Nothing is raised when the value is unchanged. Returns TRUE on a change.
/proc/om_set(datum/E, name, value) // ALLOW(base_proc): global API written before the base-type ratchet
	if(E.vars[name] == value)
		return FALSE
	var/channel = om_field_channel(E, name)
	if(!channel)
		CRASH("om_set: [E.type].[name] is not a declared field")
	E.vars[name] = value
	om_changed(E, channel)
	return TRUE

/// Raises the declared channel of `E`'s field `name` after an in-place change the setter can't
/// see (a list or datum field edited in place). Setters call it for you.
/proc/om_field_changed(datum/E, name) // ALLOW(base_proc): global API written before the base-type ratchet
	var/channel = om_field_channel(E, name)
	if(!channel)
		CRASH("om_field_changed: [E.type].[name] is not a declared field")
	om_changed(E, channel)
