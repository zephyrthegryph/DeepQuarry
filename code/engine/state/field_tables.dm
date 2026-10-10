// Declared fields (doc/rewrite/object_model_core.md §5.1).
//
// A var that a stage, behaviour or watch reads to decide whether it has work is a tracked var:
// TRACKED(T, var) declares it and its generated setter (the setter publishes the var's key, only when
// the value changed). The field definitions below are what OM_DERIVE_FIELD() and the registry still
// build (a /datum/scheduler_field_definition subtype per field).

/// One declared field (OM_DERIVE_FIELD() or the registry): /datum/scheduler_field_definition<declaring type>/<name>.
/datum/scheduler_field_definition
	parent_type = /datum/core_definition
	/// The declaring type.
	var/of
	/// The var name.
	var/field
	/// The channel its setter raises.
	var/channel = 0
	/// OM_DERIVE_FIELD(): computed by the proc named `field`; no var, no setter.
	var/derived = FALSE
	/// OM_DERIVE_FIELD(): its inputs, field names and raw channels (its channel is their union).
	var/list/inputs

/datum/definition_registry
	/// type path -> field name -> channel (every field_def whose `of` is an ancestor, merged).
	var/list/fields_by_type = list() // ALLOW(instance_list): d: registry singleton, filled per entity type on first use
	/// Every /datum/scheduler_field_definition type (read with initial(); never instantiated).
	var/list/field_defs

/// Declared fields of `path` (and its ancestors): field name -> channel.
/datum/definition_registry/proc/fields_of(path)
	RETURN_TYPE(/list)
	var/list/F = fields_by_type[path]
	if(F)
		return F
	if(!field_defs)
		field_defs = list()
		for(var/def_path in subtypesof(/datum/scheduler_field_definition))
			var/datum/scheduler_field_definition/D = def_path
			if(initial(D.field))
				field_defs += def_path
	F = scheduler_field_field_table(path)
	fields_by_type[path] = F
	return F

/// The union of the channels of the declared fields `reads` of type `path` (undeclared names add
/// nothing; check_field_reads() reports them).
/datum/definition_registry/proc/field_reads_mask(path, list/reads)
	. = 0
	if(!path || !length(reads))
		return
	var/list/F = fields_of(path)
	for(var/name in reads)
		. |= F[name]

/// Boot check: every field a stage (or behaviour) `reads` is declared, and its channel wakes it
/// (build_stages()/build_behaviours() derive that; this catches a later override).
/// Returns the problems (also recorded as registry errors).
/datum/definition_registry/proc/check_field_reads()
	. = list()
	for(var/path in stage_by_type)
		var/datum/work_stage/T = stage_by_type[path]
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
	for(var/datum/scheduled_behaviour/B as anything in behaviours)
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
/proc/scheduler_field_field_channel(datum/E, name)
	var/list/F = definition_registry().fields_of(E.type)
	return F[name] || 0

/// Raises the declared channel of `E`'s field `name` after an in-place change the setter can't
/// see (a list or datum field edited in place). Setters call it for you.
/proc/scheduler_field_field_changed(datum/E, name)
	var/channel = scheduler_field_field_channel(E, name)
	if(!channel)
		CRASH("scheduler_field_field_changed: [E.type].[name] is not a declared field")
	state_changed(E, channel)

/// Declared fields of `path` (and its ancestors), field name -> channel, with derived fields
/// resolved to the union of their inputs' channels. Usable before the registry exists (the
/// declared-periodic service build reads it); the registry caches it per type in fields_of().
/proc/scheduler_field_field_table(path)
	RETURN_TYPE(/list)
	var/static/list/plain_defs
	var/static/list/derived_defs
	if(!plain_defs)
		plain_defs = list()
		derived_defs = list()
		for(var/def_path in subtypesof(/datum/scheduler_field_definition))
			var/datum/scheduler_field_definition/D = def_path
			if(!initial(D.field))
				continue
			if(initial(D.derived))
				derived_defs += new def_path // inputs is a list: read from an instance
			else
				plain_defs += def_path
	var/list/F = list()
	for(var/datum/scheduler_field_definition/D as anything in plain_defs)
		if(ispath(path, initial(D.of)))
			F[initial(D.field)] |= initial(D.channel)
	var/list/mine = list()
	for(var/datum/scheduler_field_definition/D as anything in derived_defs)
		if(ispath(path, D.of))
			mine += D
	// Derived fields may read other derived fields: resolve until nothing changes.
	for(var/pass in 1 to max(1, length(mine)))
		var/changed = FALSE
		for(var/datum/scheduler_field_definition/D as anything in mine)
			var/channel = F[D.field]
			for(var/input in D.inputs)
				if(isnum(input))
					channel |= input
				else if(findtext(input, "."))
					// "rel.field": the relation var's own channel (relink) plus the relay's CHANGE_RELATED.
					channel |= F[copytext(input, 1, findtext(input, "."))] | CHANGE_RELATED
				else
					channel |= F[input]
			if(channel != F[D.field])
				F[D.field] = channel
				changed = TRUE
		if(!changed)
			break
	return F

/// Boot check: every derived field's inputs are declared fields of its type (or raw channels).
/proc/scheduler_field_check_derived_inputs()
	. = list()
	for(var/def_path in subtypesof(/datum/scheduler_field_definition))
		var/datum/scheduler_field_definition/proto = def_path
		if(!initial(proto.field) || !initial(proto.derived))
			continue
		var/datum/scheduler_field_definition/D = new def_path
		var/list/F = scheduler_field_field_table(D.of)
		if(!length(D.inputs))
			. += "OM_DERIVE_FIELD([D.of], [D.field]) declares no inputs"
		for(var/input in D.inputs)
			if(isnum(input))
				continue
			var/dot = findtext(input, ".")
			var/local = dot ? copytext(input, 1, dot) : input
			if(!F[local])
				. += "OM_DERIVE_FIELD([D.of], [D.field]) reads [input]: [local] is not a declared field of [D.of]"

// ---------------------------------------------------------------- cross-entity derived inputs
//
// A derived input "rel.field" reads `field` on the entity held in the holder's declared field `rel`
// (a relation view or an owned child, declared with OM_FIELD_VIEW; scheduler_field_relay_targets()). Each holder subscribes to that entity's `field` channel: the target's
// rec.relay_in names the holder, and a raise there raises CHANGE_RELATED on the holder, which is part
// of the derived field's channel. Writing `rel` (an ownership accessor, or the framework clearing it
// when its entity dies, raises its channel, the type's relay_mask) resubscribes; teardown of either
// end drops the subscription.

/// Stride 2 (relation var, field) for every cross-entity input of `path`'s derived fields.
/proc/scheduler_field_derived_relays_of(path)
	var/static/list/all // stride 3: declaring type, relation var, field (built once)
	if(!all)
		all = list()
		for(var/def_path in subtypesof(/datum/scheduler_field_definition))
			var/datum/scheduler_field_definition/proto = def_path
			if(!initial(proto.derived))
				continue
			var/datum/scheduler_field_definition/D = new def_path
			for(var/input in D.inputs)
				if(istext(input) && findtext(input, "."))
					var/dot = findtext(input, ".")
					all += list(D.of, copytext(input, 1, dot), copytext(input, dot + 1))
	var/list/out
	for(var/i in 1 to length(all) step 3)
		if(ispath(path, all[i]))
			LAZYADD(out, list(all[i + 1], all[i + 2]))
	return out

/// The entities E's field `var_name` names now, read through the ownership model
/// (doc/rewrite/ownership.md): a relation view (rel_targets(), single or list), or an owned child
/// or list of children (own_values()); anything else is a plain var read. Every writer of such a var
/// is an ownership accessor or a framework auto-clear, and each raises the field's channel (the
/// type's relay_mask), so entity_dispatch_change() calls scheduler_field_derived_relink() again whenever what this
/// returns changes, including when a related entity is destroyed.
/proc/scheduler_field_relay_targets(datum/E, var_name)
	RETURN_TYPE(/list)
	var/list/entry = own_entry(E, var_name)
	if(entry)
		switch(entry[OWNE_KIND])
			if(OWNK_REL)
				return rel_targets(E, var_name)
			if(OWNK_OWN)
				return own_values(E, var_name)
	var/value = E.vars[var_name]
	if(islist(value))
		. = list()
		for(var/datum/D in value)
			. += D
		return .
	return isdatum(value) ? list(value) : list()

/// Resubscribes E to the entities its relation vars name now.
/proc/scheduler_field_derived_relink(datum/E, datum/scheduler_record/rec)
	var/list/relays = rec.table.derived_relays
	var/list/wanted = list() // target -> mask
	for(var/i in 1 to length(relays) step 2)
		for(var/datum/target as anything in scheduler_field_relay_targets(E, relays[i]))
			if(QDELETED(target))
				continue
			var/channel = scheduler_field_field_table(target.type)[relays[i + 1]]
			if(channel)
				wanted[target] |= channel
	for(var/datum/old as anything in rec.relay_out?.Copy())
		if(!wanted[old])
			scheduler_field_relay_remove(E, rec, old)
	for(var/datum/target as anything in wanted)
		var/datum/scheduler_record/trec = scheduler_record_of(target)
		if(!trec)
			continue
		var/found = FALSE
		for(var/j in 1 to length(trec.relay_in) step 2)
			if(trec.relay_in[j] == E)
				trec.relay_in[j + 1] = wanted[target]
				found = TRUE
				break
		if(!found)
			LAZYADD(trec.relay_in, list(E, wanted[target]))
			LAZYOR(rec.relay_out, target)
		entity_recompute_listen(trec)

/proc/scheduler_field_relay_remove(datum/E, datum/scheduler_record/rec, datum/target)
	LAZYREMOVE(rec.relay_out, target)
	var/datum/scheduler_record/trec = target.om_rec
	if(!trec?.relay_in)
		return
	for(var/j in 1 to length(trec.relay_in) step 2)
		if(trec.relay_in[j] == E)
			trec.relay_in.Cut(j, j + 2)
			break
	if(!length(trec.relay_in))
		trec.relay_in = null
	entity_recompute_listen(trec)

/// Teardown (links phase): E stops relaying from its targets, and its holders stop relaying from E.
/proc/scheduler_field_relay_clear(datum/E, datum/scheduler_record/rec)
	for(var/datum/target as anything in rec.relay_out?.Copy())
		scheduler_field_relay_remove(E, rec, target)
	rec.relay_out = null
	for(var/j in 1 to length(rec.relay_in) step 2)
		var/datum/holder = rec.relay_in[j]
		var/datum/scheduler_record/hrec = holder?.om_rec
		if(hrec)
			LAZYREMOVE(hrec.relay_out, E)
			state_changed(holder, CHANGE_RELATED) // what it read is going away
	rec.relay_in = null
