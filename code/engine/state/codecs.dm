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
	var/value_handle = isdatum(value) && ctx.ids && entity_handle(value)
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
		var/target_handle = ctx.ids && entity_handle(target)
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
// atom_flags: /atom/var/flags without its runtime bits (ATOM_RUNTIME_FLAGS: initialized, materialized).
// ---------------------------------------------------------------------------
/datum/state_codec/atom_flags

/datum/state_codec/atom_flags/encode(datum/owner, var_name, value, datum/state_context/ctx)
	return value & ~ATOM_RUNTIME_FLAGS

/datum/state_codec/atom_flags/decode(datum/owner, var_name, encoded, datum/state_context/ctx)
	owner.vars[var_name] = (owner.vars[var_name] & ATOM_RUNTIME_FLAGS) | (encoded & ~ATOM_RUNTIME_FLAGS) // ALLOW(api): state serializer codecs

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
