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
	owner.vars[var_name] = ctx.decode_value(encoded) // ALLOW(api): state serializer codecs

// ---------------------------------------------------------------------------
// child: a reference to an object in the same subtree. encode_value() already
// does this for any reference it finds in the subtree; declaring the codec
// states the intent, and refuses a value outside the subtree.
// ---------------------------------------------------------------------------
/datum/state_codec/child

/datum/state_codec/child/encode(datum/owner, var_name, value, datum/state_context/ctx)
	if(isnull(value))
		return null
	var/value_handle = isdatum(value) && ctx.ids && om_handle(value)
	if(!value_handle || !(value_handle in ctx.ids))
		ctx.refuse("[owner.type].[var_name] refers to [value] outside the subtree")
		return null
	return list(STATE_WRAP_CHILD = ctx.ids[value_handle])

// ---------------------------------------------------------------------------
// Ownership codecs (doc/rewrite/ownership.md §6). A saved var with no codec of
// its own gets one from its ownership kind (state_ownership_codec()): owned
// values nest as blobs, proto vars save a prototype id or a private blob, and
// relation views save a child id inside the subtree (a view leaving the subtree
// is dropped: relations are non-owning, and the loader re-links what it can).
// ---------------------------------------------------------------------------

/// The codec path ownership implies for D.var_name holding `value`, or null.
/proc/state_ownership_codec(datum/D, var_name, value)
	var/list/entry = own_table_of(D).entries[var_name]
	var/kind = entry?[OWNE_KIND]
	if(!kind)
		var/datum/V = value
		if(isdatum(V) && V.own_holder_ref == own_key(D))
			kind = OWNK_OWN
		else if(islist(value))
			for(var/datum/member in value)
				if(member.own_holder_ref == own_key(D))
					kind = OWNK_OWN
				break
	switch(kind)
		if(OWNK_OWN)
			return /datum/state_codec/owned
		if(OWNK_PROTO)
			return /datum/state_codec/proto
		if(OWNK_REL)
			return /datum/state_codec/relation
	return null

// owned: the value(s) only this owner holds, each saved as its own nested blob
// (type plus saved vars). An atom in the subtree is a child reference instead.
/datum/state_codec/owned

/datum/state_codec/owned/encode(datum/owner, var_name, value, datum/state_context/ctx)
	if(isnull(value))
		return null
	if(islist(value))
		var/list/out = list()
		var/list/L = value
		for(var/key in L)
			var/datum/member = (!isnum(key) && isdatum(L[key])) ? L[key] : key
			var/encoded_member = encode_one(owner, var_name, member, ctx)
			if(ctx.errors)
				return null
			if(member == key)
				out += list(encoded_member)
			else
				out += list(list(ctx.encode_value(key, "[owner.type].[var_name] key"), encoded_member))
		return list(STATE_WRAP_OWNED = out, "shape" = state_list_is_assoc(L) ? "values" : "list")
	return list(STATE_WRAP_OWNED = encode_one(owner, var_name, value, ctx))

/datum/state_codec/owned/proc/encode_one(datum/owner, var_name, datum/value, datum/state_context/ctx)
	if(!isdatum(value))
		return ctx.encode_value(value, "[owner.type].[var_name]")
	if(isatom(value))
		return ctx.encode_value(value, "[owner.type].[var_name]") // a child in the subtree, or refused
	return ctx.serialize_datum(value, NONE)

/// Decodes into owner.var_name through the ownership accessors. A one-shape var whose current
/// child has the saved type is reused (the blob applied onto it); otherwise the old child is
/// disposed of and the new one adopted.
/datum/state_codec/owned/decode(datum/owner, var_name, encoded, datum/state_context/ctx)
	if(isnull(encoded))
		rel_clear(owner, var_name)
		return
	var/nested = encoded[STATE_WRAP_OWNED]
	var/shape = encoded["shape"]
	if(!shape)
		var/datum/current = owner.vars[var_name]
		if(islist(nested) && nested[STATE_KEY_TYPE] && isdatum(current) && "[current.type]" == nested[STATE_KEY_TYPE] && !isatom(current))
			ctx.apply_datum(current, nested)
			return
		rel_set(owner, var_name, decode_one(nested, ctx))
		return
	rel_clear(owner, var_name)
	for(var/item in nested)
		if(shape == "values")
			var/list/pair = item
			rel_add(owner, var_name, decode_one(pair[2], ctx), ctx.decode_value(pair[1]))
		else
			rel_add(owner, var_name, decode_one(item, ctx))

/datum/state_codec/owned/proc/decode_one(nested, datum/state_context/ctx)
	if(islist(nested) && nested[STATE_KEY_TYPE])
		return ctx.materialize_datum(nested)
	return ctx.decode_value(nested)

// proto: a registered prototype saves its registry id; a private copy saves as an owned blob.
/datum/state_codec/proto

/datum/state_codec/proto/encode(datum/owner, var_name, value, datum/state_context/ctx)
	if(isnull(value))
		return null
	if(proto_is_private(owner, var_name))
		return list("#private" = ctx.serialize_datum(value, NONE))
	return ctx.encode_value(value, "[owner.type].[var_name]")

/datum/state_codec/proto/decode(datum/owner, var_name, encoded, datum/state_context/ctx)
	if(islist(encoded) && encoded["#private"])
		proto_set(owner, var_name, ctx.materialize_datum(encoded["#private"]))
		return
	proto_set(owner, var_name, ctx.decode_value(encoded))

// relation: a REF view. Targets inside the subtree save as child ids and re-link on load;
// targets outside it are dropped.
/datum/state_codec/relation

/datum/state_codec/relation/encode(datum/owner, var_name, value, datum/state_context/ctx)
	if(isnull(value))
		return null
	var/list/targets = islist(value) ? value : list(value)
	var/list/out = list()
	for(var/datum/target as anything in targets)
		var/target_handle = ctx.ids && om_handle(target)
		if(target_handle && (target_handle in ctx.ids))
			out += list(list(STATE_WRAP_CHILD = ctx.ids[target_handle]))
	if(!length(out))
		return null
	return islist(value) ? list("#views" = out) : out[1]

/datum/state_codec/relation/decode(datum/owner, var_name, encoded, datum/state_context/ctx)
	rel_clear(owner, var_name)
	if(isnull(encoded))
		return
	if(islist(encoded) && encoded["#views"])
		for(var/item in encoded["#views"])
			var/datum/target = ctx.decode_value(item)
			if(isdatum(target))
				rel_add(owner, var_name, target)
		return
	var/datum/target = ctx.decode_value(encoded)
	if(isdatum(target))
		rel_set(owner, var_name, target)

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
	owner.vars[var_name] = (owner.vars[var_name] & ATOM_RUNTIME_FLAGS) | (encoded & ~ATOM_RUNTIME_FLAGS) // ALLOW(api): state serializer codecs

// ---------------------------------------------------------------------------
// frame_type: /obj/item/circuitboard/board_type (roadmap C6, containment.md
// section 5). Usually a /datum/frame/frame_types instance owned only by this
// board (an `owned` nested blob), but some boards set it to a plain string
// ("other") instead -- circuitboard.dm's own comment: "Some boards use text
// instead of an instance". frame_types itself needs no codec of its own: its
// vars (name, frame_size, frame_class, a circuit type path, frame_style,
// x_offset, y_offset, an icon_override resource) are all plain values the
// generic encoder already handles.
// ---------------------------------------------------------------------------
/datum/state_codec/frame_type

/datum/state_codec/frame_type/encode(datum/owner, var_name, value, datum/state_context/ctx)
	if(isnull(value))
		return null
	if(!isdatum(value))
		return ctx.encode_value(value, "[owner.type].[var_name]")
	if(isatom(value))
		ctx.refuse("[owner.type].[var_name] is a frame_type codec but holds an atom")
		return null
	var/list/nested = ctx.serialize_datum(value, NONE)
	if(!nested)
		return null
	return list(STATE_WRAP_OWNED = nested)

/datum/state_codec/frame_type/decode(datum/owner, var_name, encoded, datum/state_context/ctx)
	if(isnull(encoded))
		owner.vars[var_name] = null // ALLOW(api): state serializer codecs
		return
	if(!islist(encoded))
		owner.vars[var_name] = encoded // ALLOW(api): state serializer codecs
		return
	var/list/nested = encoded[STATE_WRAP_OWNED]
	owner.vars[var_name] = ctx.materialize_datum(nested) // ALLOW(api): state serializer codecs

// ---------------------------------------------------------------------------
// pinned: an owned child that holds live wiring (hooks registered in New(), back
// references, a hosted mind) and cannot be rebuilt from saved vars. While it is
// set the holder is not serialized, so it stays materialised; while it is null
// the holder saves normally. This is the declared form of "not saved: keeps the
// holder live", in place of a reference the serializer would refuse unannounced.
// ---------------------------------------------------------------------------
/datum/state_codec/pinned

/datum/state_codec/pinned/encode(datum/owner, var_name, value, datum/state_context/ctx)
	if(isnull(value))
		return null
	ctx.refuse("[owner.type].[var_name] holds live state ([value]) and pins its holder materialised")
	return null

/datum/state_codec/pinned/decode(datum/owner, var_name, encoded, datum/state_context/ctx)
	return

