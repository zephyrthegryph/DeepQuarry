/*
 * Codecs for the state serializer (doc/rewrite/state.md section 3).
 *
 * Every value goes through /datum/state_context/proc/encode_value(), which
 * handles plain values, lists, paths, resources, children in the subtree and
 * registry singletons, and refuses anything else. A var listed in its type's
 * state_codecs() goes through that codec instead. Codecs are stateless
 * singletons, fetched with state_codec(path).
 */

GLOBAL_LIST_EMPTY(state_codec_instances)

/proc/state_codec(path)
	var/datum/state_codec/codec = GLOB.state_codec_instances[path]
	if(!codec)
		codec = new path
		GLOB.state_codec_instances[path] = codec
	return codec

/datum/state_codec

/// Returns the encoded value. Call ctx.refuse() and return null to refuse.
/datum/state_codec/proc/encode(datum/owner, var_name, value, datum/state_context/ctx)
	return ctx.encode_value(value, "[owner.type].[var_name]")

/// Writes the decoded value into owner.vars[var_name] (or does whatever the var needs).
/datum/state_codec/proc/decode(datum/owner, var_name, encoded, datum/state_context/ctx)
	owner.vars[var_name] = ctx.decode_value(encoded)

// ---------------------------------------------------------------------------
// child: a reference to an object in the same subtree. encode_value() already
// does this for any reference it finds in the subtree; declaring the codec
// states the intent, and refuses a value outside the subtree.
// ---------------------------------------------------------------------------
/datum/state_codec/child

/datum/state_codec/child/encode(datum/owner, var_name, value, datum/state_context/ctx)
	if(isnull(value))
		return null
	if(!isdatum(value) || !ctx.ids || !(value in ctx.ids))
		ctx.refuse("[owner.type].[var_name] refers to [value] outside the subtree")
		return null
	return list(STATE_WRAP_CHILD = ctx.ids[value])

// ---------------------------------------------------------------------------
// owned: a datum only this owner refers to, saved as its own nested blob
// (type plus saved vars). The datum's refs go through the same codecs.
// ---------------------------------------------------------------------------
/datum/state_codec/owned

/datum/state_codec/owned/encode(datum/owner, var_name, value, datum/state_context/ctx)
	if(isnull(value))
		return null
	if(!isdatum(value) || isatom(value))
		ctx.refuse("[owner.type].[var_name] is an owned codec but holds [value]")
		return null
	var/list/nested = ctx.serialize_datum(value, NONE)
	if(!nested)
		return null
	return list(STATE_WRAP_OWNED = nested)

/datum/state_codec/owned/decode(datum/owner, var_name, encoded, datum/state_context/ctx)
	if(isnull(encoded))
		owner.vars[var_name] = null
		return
	var/list/nested = encoded[STATE_WRAP_OWNED]
	owner.vars[var_name] = ctx.materialize_datum(nested)

// ---------------------------------------------------------------------------
// reagents: the /datum/reagents holder, as its capacity and its reagents.
// ---------------------------------------------------------------------------
/datum/state_codec/reagents

/datum/state_codec/reagents/encode(datum/owner, var_name, value, datum/state_context/ctx)
	var/datum/reagents/holder = value
	if(isnull(holder))
		return null
	if(!istype(holder))
		ctx.refuse("[owner.type].[var_name] holds [holder], not a reagent holder")
		return null
	var/list/reagents = list()
	for(var/datum/reagent/R as anything in holder.reagent_list)
		var/data = isnull(R.data) ? null : ctx.encode_value(R.data, "[owner.type].[var_name] [R.id] data")
		reagents += list(list(R.id, R.volume, data))
	return list("max" = holder.maximum_volume, "list" = reagents)

/datum/state_codec/reagents/decode(datum/owner, var_name, encoded, datum/state_context/ctx)
	var/atom/A = owner
	if(!istype(A))
		ctx.refuse("the reagents codec needs an atom, got [owner.type]")
		return
	if(isnull(encoded))
		QDEL_NULL(A.reagents)
		return
	if(!A.reagents)
		A.create_reagents(encoded["max"])
	var/datum/reagents/holder = A.reagents
	holder.clear_reagents()
	holder.maximum_volume = encoded["max"]
	for(var/list/entry as anything in encoded["list"])
		// safety = TRUE: the saved mix was stable, so adding it back must not react.
		holder.add_reagent(entry[1], entry[2], ctx.decode_value(entry[3]), TRUE)

// ---------------------------------------------------------------------------
// atom_flags: /atom/var/flags without its runtime bits (ATOM_RUNTIME_FLAGS: initialized, materialized).
// ---------------------------------------------------------------------------
/datum/state_codec/atom_flags

/datum/state_codec/atom_flags/encode(datum/owner, var_name, value, datum/state_context/ctx)
	return value & ~ATOM_RUNTIME_FLAGS

/datum/state_codec/atom_flags/decode(datum/owner, var_name, encoded, datum/state_context/ctx)
	owner.vars[var_name] = (owner.vars[var_name] & ATOM_RUNTIME_FLAGS) | (encoded & ~ATOM_RUNTIME_FLAGS)
