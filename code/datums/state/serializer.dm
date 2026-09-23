/*
 * The state serializer (doc/rewrite/state.md sections 2-5). The public API and
 * the blob format are described in schema.dm; this file is the engine.
 *
 * One /datum/state_context runs one serialize, materialize or apply call. It
 * holds the flags, the errors, and the child IDs of the subtree: "" is the
 * root, "2" its second content, "2.1" that content's first content.
 */

/// Per-type schema, built from the first instance serialized and cached.
/datum/state_schema
	var/type_path
	/// Saved var names, in the order BYOND lists them.
	var/list/saved_vars
	/// var name -> codec path, from state_codecs().
	var/list/codecs
	/// var name -> encoded pristine value, for list vars of latent-safe types (null otherwise).
	var/list/list_baseline

GLOBAL_LIST_EMPTY(state_schemas)

/// Built-in vars of every datum; none is saved.
GLOBAL_LIST_INIT(state_datum_builtin_vars, list("type", "parent_type", "vars", "tag"))

/// Built-in vars of atoms. Only STATE_BUILTIN_SAVED of them are part of a schema.
GLOBAL_LIST_INIT(state_builtin_vars, list(
	"type", "parent_type", "vars", "tag", "loc", "locs", "x", "y", "z", "contents",
	"verbs", "overlays", "underlays", "vis_contents", "vis_locs", "vis_flags", "appearance",
	"appearance_flags", "filters", "particles", "transform", "render_source", "render_target",
	"blend_mode", "layer", "plane", "luminosity", "infra_luminosity", "mouse_opacity",
	"mouse_over_pointer", "mouse_drag_pointer", "mouse_drop_pointer", "mouse_drop_zone",
	"screen_loc", "suffix", "text", "icon_w", "icon_z", "maptext_width", "maptext_height",
	"maptext_x", "maptext_y", "animate_movement", "bound_x", "bound_y", "bound_width",
	"bound_height", "glide_size", "step_size", "step_x", "step_y", "override", "ckey", "key",
	"client", "group", "see_in_dark", "see_infrared", "see_invisible", "sight",
	"name", "desc", "icon", "icon_state", "dir", "color", "alpha", "pixel_x", "pixel_y",
	"pixel_w", "pixel_z", "density", "opacity", "invisibility", "gender", "maptext",
))

/proc/state_schema_for(datum/D)
	var/datum/state_schema/schema = GLOB.state_schemas[D.type]
	if(schema)
		return schema
	schema = new
	schema.type_path = D.type
	schema.saved_vars = list()
	var/static/list/builtin_saved = STATE_BUILTIN_SAVED
	var/list/builtins = isatom(D) ? GLOB.state_builtin_vars : GLOB.state_datum_builtin_vars
	for(var/name in D.vars)
		if((name in builtins) && !(name in builtin_saved))
			continue
		if(!issaved(D.vars[name]))
			continue
		schema.saved_vars += name
	schema.codecs = D.state_codecs()
	GLOB.state_schemas[D.type] = schema
	return schema

/// Canonical form: assoc keys sorted, numbers normalized, recursively.
/proc/state_canonicalize(value)
	if(isnum(value))
		if(value == round(value))
			return value
		return round(value, 0.000001)
	if(!islist(value))
		return value
	var/list/L = value
	if(!state_list_is_assoc(L))
		. = list()
		for(var/item in L)
			. += list(state_canonicalize(item))
		return .
	var/list/keys = list()
	for(var/key in L)
		keys += "[key]"
	sortTim(keys, GLOBAL_PROC_REF(cmp_text_asc))
	. = list()
	for(var/key in keys)
		.[key] = state_canonicalize(L[key])

/// TRUE if the list has at least one non-number key with an associated value.
/proc/state_list_is_assoc(list/L)
	for(var/key in L)
		if(isnum(key))
			continue
		if(!isnull(L[key]))
			return TRUE
	return FALSE

/datum/state_context
	var/flags = NONE
	/// Reasons the call failed; null when it succeeded.
	var/list/errors
	/// Serialize: datum -> child ID for every atom in the subtree.
	var/list/ids
	/// Materialize: child ID -> atom.
	var/list/by_id
	/// Materialize: list(target, blob) pairs whose vars are applied once the tree exists.
	var/list/pending
	/// The root is latent-safe: list vars of the whole subtree compare against pristine instances.
	var/latent_root = FALSE

/datum/state_context/New(flags)
	..()
	src.flags = flags

/datum/state_context/Destroy(force)
	ids = null
	by_id = null
	pending = null
	return ..()

/datum/state_context/proc/refuse(reason)
	LAZYADD(errors, reason)

// ---------------------------------------------------------------------------
// Serialize
// ---------------------------------------------------------------------------

/datum/state_context/proc/serialize_root(datum/D)
	if(!istype(D) || QDELETED(D))
		refuse("[D] is not a live datum")
		return null
	ids = list()
	ids[D] = ""
	var/atom/movable/movable = D
	latent_root = istype(movable) && movable.latent_safe
	if((flags & STATE_CONTENTS) && isatom(D))
		assign_ids(D, "")
	. = serialize_datum(D, flags)
	if(errors)
		return null

/datum/state_context/proc/assign_ids(atom/A, prefix)
	var/index = 0
	for(var/atom/movable/child as anything in state_children(A))
		index++
		var/id = prefix == "" ? "[index]" : "[prefix].[index]"
		ids[child] = id
		assign_ids(child, id)

/// Serializes one datum: type, version, delta, and (per flags) contents and components.
/datum/state_context/proc/serialize_datum(datum/D, flags)
	if(ismob(D))
		refuse("[D.type] is a mob; mobs stay real")
		return null
	var/refusal = D.state_refusal()
	if(refusal)
		refuse("[D.type] [refusal]")
		return null
	var/datum/state_schema/schema = state_schema_for(D)
	var/list/blob = list()
	blob[STATE_KEY_TYPE] = "[D.type]"
	blob[STATE_KEY_VERSION] = D.state_version
	var/list/delta = encode_delta(D, schema)
	if(length(delta))
		blob[STATE_KEY_VARS] = delta
	if((flags & STATE_CONTENTS) && isatom(D))
		var/atom/A = D
		var/list/children = list()
		for(var/atom/movable/child as anything in state_children(A))
			var/list/child_blob = serialize_datum(child, flags)
			if(!child_blob)
				return null
			children += list(child_blob)
		blob[STATE_KEY_CONTENTS] = children
	if(flags & STATE_COMPONENTS)
		var/list/components = serialize_components(D)
		if(errors)
			return null
		if(length(components))
			blob[STATE_KEY_COMPONENTS] = components
	return errors ? null : blob

/datum/state_context/proc/encode_delta(datum/D, datum/state_schema/schema)
	var/list/delta = list()
	var/list/excluded = D.state_exclude()
	var/list/variant = D.state_variant_baseline()
	var/latent = latent_root && ismovable(D)
	for(var/name in schema.saved_vars)
		if(name in excluded)
			continue
		var/value = D.vars[name]
		if(variant && (name in variant) && variant[name] == value)
			continue
		var/codec_path = schema.codecs[name]
		if(!codec_path && !islist(value) && value == initial(D.vars[name]))
			continue
		var/encoded
		if(codec_path)
			var/default = initial(D.vars[name])
			if(value == default)
				continue
			var/datum/state_codec/codec = state_codec(codec_path)
			encoded = codec.encode(D, name, value, src)
			// A codec may drop runtime parts of a value, leaving the default.
			if(!islist(encoded) && encoded == default)
				continue
		else
			encoded = encode_value(value, "[D.type].[name]")
		if(islist(value) && list_matches_baseline(D, schema, name, encoded, latent))
			continue
		delta[name] = encoded
	return delta

/// Lists have no usable initial(), so other types save every list var that is
/// set (as the pre-L1 serializer did). In a latent-safe subtree a list matches
/// the pristine instance's value, and an empty list matches an unset one.
/datum/state_context/proc/list_matches_baseline(datum/D, datum/state_schema/schema, name, encoded, latent)
	if(!latent)
		return FALSE
	var/list/L = D.vars[name]
	var/list/baselines = list_baseline_of(D.type)
	var/baseline = baselines[name]
	if(isnull(baseline))
		return !length(L)
	return state_canonical(baseline) == state_canonical(encoded)

/// Encoded list vars of a pristine instance of `path`, made once and cached on its schema.
/datum/state_context/proc/list_baseline_of(path)
	var/datum/state_schema/schema = GLOB.state_schemas[path]
	if(schema?.list_baseline)
		return schema.list_baseline
	var/list/baseline = pristine_lists(path)
	schema = GLOB.state_schemas[path]
	schema.list_baseline = baseline
	return baseline

/// Encoded list vars of a fresh instance of `path`, for latent-safe types.
/datum/state_context/proc/pristine_lists(path)
	. = list()
	var/datum/probe = new_unmaterialized(path, null) // sandboxed: no world registration (L2)
	var/datum/state_context/probe_ctx = new(NONE)
	probe_ctx.ids = list()
	var/datum/state_schema/schema = state_schema_for(probe)
	for(var/name in schema.saved_vars)
		var/value = probe.vars[name]
		if(!islist(value))
			continue
		var/encoded = probe_ctx.encode_value(value, "[path].[name]")
		if(!probe_ctx.errors)
			.[name] = encoded
		probe_ctx.errors = null
	qdel(probe_ctx)
	qdel(probe)

/datum/state_context/proc/serialize_components(datum/D)
	var/list/unique = list()
	for(var/key in D._datum_components)
		var/entry = D._datum_components[key]
		if(islist(entry))
			for(var/datum/component/C as anything in entry)
				unique |= C
		else
			unique |= entry
	var/list/by_type = list()
	for(var/datum/component/C as anything in unique)
		switch(C.state_mode)
			if(STATE_COMPONENT_DERIVED)
				continue
			if(STATE_COMPONENT_REFUSE)
				refuse("[D.type] has component [C.type], which cannot be serialized")
				return null
		var/list/component_blob = serialize_datum(C, NONE)
		if(!component_blob)
			return null
		by_type["[C.type]"] = component_blob
	if(!length(by_type))
		return null
	var/list/keys = list()
	for(var/key in by_type)
		keys += key
	sortTim(keys, GLOBAL_PROC_REF(cmp_text_asc))
	. = list()
	for(var/key in keys)
		. += list(by_type[key])

/// Encodes one value. `where` names the var for error messages.
/datum/state_context/proc/encode_value(value, where)
	if(isnull(value) || isnum(value) || istext(value))
		return value
	if(ispath(value))
		return list(STATE_WRAP_PATH = "[value]")
	if(islist(value))
		return encode_list(value, where)
	if(isfile(value))
		return list(STATE_WRAP_RESOURCE = "[value]")
	if(isdatum(value))
		if(ids && (value in ids))
			return list(STATE_WRAP_CHILD = ids[value])
		var/list/registry = state_registry_id(value)
		if(registry)
			return list(STATE_WRAP_REGISTRY = registry)
		var/datum/ref = value
		refuse("[where] refers to [ref.type], which has no codec")
		return null
	refuse("[where] holds [value], which cannot be encoded")
	return null

/datum/state_context/proc/encode_list(list/L, where)
	if(!state_list_is_assoc(L))
		. = list()
		for(var/item in L)
			. += list(encode_value(item, where))
		return .
	var/text_keys = TRUE
	for(var/key in L)
		if(!istext(key))
			text_keys = FALSE
			break
	if(text_keys)
		. = list()
		for(var/key in L)
			var/out_key = copytext(key, 1, 2) == STATE_ESCAPE ? "[STATE_ESCAPE][key]" : key
			.[out_key] = encode_value(L[key], where)
		return .
	var/list/pairs = list()
	for(var/key in L)
		pairs += list(list(encode_value(key, where), encode_value(isnum(key) ? null : L[key], where)))
	return list(STATE_WRAP_PAIRS = pairs)

/// list(kind, id) for a registered singleton, or null.
/proc/state_registry_id(datum/D)
	if(istype(D, /datum/material))
		var/datum/material/M = D
		if(GLOB.name_to_material[M.name] == M)
			return list(STATE_REGISTRY_MATERIAL, M.name)
	else if(istype(D, /datum/decl))
		if(GET_DECL(D.type) == D)
			return list(STATE_REGISTRY_DECL, "[D.type]")
	else if(istype(D, /datum/species))
		var/datum/species/S = D
		if(GLOB.all_species[S.name] == S)
			return list(STATE_REGISTRY_SPECIES, S.name)
	else if(istype(D, /datum/reagent))
		var/datum/reagent/R = D
		if(SSchemistry.chemical_reagents[R.id] == R)
			return list(STATE_REGISTRY_REAGENT, R.id)
	return null

/proc/state_registry_lookup(list/registry)
	var/id = registry[2]
	switch(registry[1])
		if(STATE_REGISTRY_MATERIAL)
			return GLOB.name_to_material[id]
		if(STATE_REGISTRY_DECL)
			return GET_DECL(text2path(id))
		if(STATE_REGISTRY_SPECIES)
			return GLOB.all_species[id]
		if(STATE_REGISTRY_REAGENT)
			return SSchemistry.chemical_reagents[id]
	return null

// ---------------------------------------------------------------------------
// Materialize and apply
// ---------------------------------------------------------------------------

/// Upgrades a blob in place to the current format and its type's current
/// version. Returns the (possibly new) type path, or null to drop the blob.
/datum/state_context/proc/migrate_blob(list/blob)
	if(!islist(blob) || !blob[STATE_KEY_TYPE])
		refuse("blob has no type")
		return null
	// Legacy flat blobs (the pre-L1 /datum/proc/serialize()): every key but "type" is a var.
	if(isnull(blob[STATE_KEY_VERSION]) && isnull(blob[STATE_KEY_VARS]))
		var/list/vars = list()
		for(var/key in blob)
			if(key != STATE_KEY_TYPE)
				vars[key] = blob[key]
		for(var/key in vars)
			blob -= key
		blob[STATE_KEY_VARS] = vars
		blob[STATE_KEY_VERSION] = STATE_VERSION_LEGACY
	var/type_text = blob[STATE_KEY_TYPE]
	var/path
	if(type_text in GLOB.state_type_migrations)
		path = GLOB.state_type_migrations[type_text]
		if(!path)
			return null
		blob[STATE_KEY_TYPE] = "[path]"
	else
		path = text2path(type_text)
	if(!path)
		refuse("unknown type [type_text] and no migration for it")
		return null
	return path

/datum/state_context/proc/materialize_root(list/blob, loc)
	by_id = list()
	pending = list()
	var/datum/D = create_tree(blob, loc, "")
	if(!D)
		return null
	finish_tree()
	if(errors)
		qdel(D)
		return null
	return D

/datum/state_context/proc/apply_root(datum/D, list/blob)
	by_id = list()
	pending = list()
	var/path = migrate_blob(blob)
	if(!path)
		return FALSE
	if(path != D.type)
		refuse("blob is a [path], target is a [D.type]")
		return FALSE
	by_id[""] = D
	pending += list(list(D, blob))
	if(isatom(D))
		create_children(D, blob, "")
	finish_tree()
	return !errors

/// Creates the object for `blob` and, recursively, its contents. Vars are applied later.
/datum/state_context/proc/create_tree(list/blob, loc, id)
	var/path = migrate_blob(blob)
	if(!path)
		return null
	var/datum/D = ispath(path, /atom) ? new path(loc) : new path
	by_id[id] = D
	pending += list(list(D, blob))
	if(isatom(D))
		create_children(D, blob, id)
	return D

/// Replaces the atom's current contents (made by Initialize) with the blob's.
/datum/state_context/proc/create_children(atom/A, list/blob, id)
	if(!(flags & STATE_CONTENTS) || !islist(blob[STATE_KEY_CONTENTS]))
		return
	var/list/removed = list()
	for(var/atom/movable/existing as anything in A.contents)
		if(ismob(existing))
			continue
		removed += existing
	for(var/atom/movable/existing as anything in removed)
		qdel(existing)
	// Vars still pointing at the removed contents were set by Initialize; the
	// delta sets them again if the saved object had them.
	if(length(removed))
		for(var/name in A.vars)
			var/value = A.vars[name]
			if(isdatum(value) && (value in removed))
				A.vars[name] = null
	var/index = 0
	for(var/list/child_blob as anything in blob[STATE_KEY_CONTENTS])
		index++
		create_tree(child_blob, A, id == "" ? "[index]" : "[id].[index]")

/// Applies vars and components everywhere, then runs state_post_apply() children first.
/datum/state_context/proc/finish_tree()
	for(var/list/entry as anything in pending)
		apply_vars(entry[1], entry[2])
		if(flags & STATE_COMPONENTS)
			apply_components(entry[1], entry[2])
	for(var/i = length(pending), i >= 1, i--)
		var/list/entry = pending[i]
		var/datum/D = entry[1]
		D.state_post_apply(entry[2], flags)

/datum/state_context/proc/apply_vars(datum/D, list/blob)
	var/list/vars = blob[STATE_KEY_VARS] || list()
	var/from_version = blob[STATE_KEY_VERSION]
	if(isnull(from_version))
		from_version = STATE_VERSION_DEFAULT
	if(from_version != D.state_version)
		D.state_migrate(vars, from_version)
	D.state_pre_apply(vars, flags)
	var/datum/state_schema/schema = state_schema_for(D)
	// The delta is the difference from initial(), so every other saved scalar
	// goes back to its default: Initialize() may have rolled something else.
	var/list/excluded = D.state_exclude()
	var/list/variant = D.state_variant_baseline()
	for(var/name in schema.saved_vars)
		if((name in vars) || (name in excluded) || (name in variant) || schema.codecs[name])
			continue
		var/value = D.vars[name]
		if(islist(value))
			continue
		var/default = initial(D.vars[name])
		if(value != default && !islist(default))
			D.vars[name] = default
	for(var/name in vars)
		if(!(name in schema.saved_vars))
			// The pre-L1 loader ignored keys it did not save; keep doing that for legacy blobs.
			if(from_version != STATE_VERSION_LEGACY)
				refuse("[D.type] has no saved var [name]; add a state_migrate() step")
			continue
		var/codec_path = schema.codecs[name]
		if(codec_path)
			var/datum/state_codec/codec = state_codec(codec_path)
			codec.decode(D, name, vars[name], src)
		else
			D.vars[name] = decode_value(vars[name])

/datum/state_context/proc/apply_components(datum/D, list/blob)
	for(var/list/component_blob as anything in blob[STATE_KEY_COMPONENTS])
		var/path = migrate_blob(component_blob)
		if(!path)
			continue
		var/datum/component/C = D.GetComponent(path) || D.AddComponent(path)
		if(!C)
			refuse("[D.type] refused component [path]")
			continue
		apply_vars(C, component_blob)
		C.state_post_apply(component_blob, flags)

/// A datum from a nested blob (the owned codec): new, then its vars.
/datum/state_context/proc/materialize_datum(list/blob)
	var/path = migrate_blob(blob)
	if(!path)
		return null
	var/datum/D = new path
	apply_vars(D, blob)
	D.state_post_apply(blob, NONE)
	return D

/datum/state_context/proc/decode_value(value)
	if(!islist(value))
		return value
	var/list/L = value
	if(length(L) == 1)
		var/key = L[1]
		if(istext(key) && copytext(key, 1, 2) == STATE_ESCAPE && copytext(key, 2, 3) != STATE_ESCAPE)
			var/inner = L[key]
			switch(key)
				if(STATE_WRAP_PATH)
					return text2path(inner)
				if(STATE_WRAP_CHILD)
					if(!(inner in by_id))
						refuse("child [inner] is not in the subtree")
						return null
					return by_id[inner]
				if(STATE_WRAP_REGISTRY)
					var/found = state_registry_lookup(inner)
					if(!found)
						refuse("registry entry [json_encode(inner)] is gone")
					return found
				if(STATE_WRAP_RESOURCE)
					return file(inner)
				if(STATE_WRAP_PAIRS)
					. = list()
					for(var/list/pair as anything in inner)
						var/pair_key = decode_value(pair[1])
						if(isnull(pair[2]))
							. += list(pair_key)
						else
							.[pair_key] = decode_value(pair[2])
					return .
				if(STATE_WRAP_OWNED)
					return materialize_datum(inner)
	if(!state_list_is_assoc(L))
		. = list()
		for(var/item in L)
			. += list(decode_value(item))
		return .
	. = list()
	for(var/key in L)
		var/out_key = copytext(key, 1, 3) == "[STATE_ESCAPE][STATE_ESCAPE]" ? copytext(key, 2) : key
		.[out_key] = decode_value(L[key])

/// Children in child-ID order. A holder with slots numbers them in its
/// ledger's order (slots in declaration order, each in insertion order), so a
/// child's ID doesn't depend on unrelated contents order.
/proc/state_children(atom/A)
	var/datum/ledger/L = dq_ledger(A)
	return L ? L.ordered() : A.contents
