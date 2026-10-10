// Capability definitions (doc/rewrite/final_api.html, section 11 "Defining one", "Keys and repeats"; section 19 "E1").
//
// A capability is a named, parameterised bundle of entries. Its DEFINITION is one interned /datum/capability: the constructor
// call `mirror_plating(reflect_chance = 45)` builds it from the CAPABILITY_TYPE (a datum whose vars are the params) or the
// CAPABILITY_DEF (a body returning entries), and cap_intern() makes every identical call one shared datum. A capability's key is
// (CAP_X, selector): the definition says which param is the selector with key =, or NONE when there is only ever one.
//
// The legacy form (the datum a cap_<noun>() constructor returns, with `key` = its type) is accepted beside it: such a datum has no
// cap_id, and the table builder keys it by its `key` as before.

/datum/capability
	/// The id the definition was declared with (CAP_X), or null for a legacy capability.
	var/cap_id
	/// The selector that tells two uses of the capability on one holder apart (cover("hatch")), or null.
	var/selector
	/// The named params the constructor call set (what configure() changes and the definition is rebuilt from).
	var/list/ctor

/// The facts one CAPABILITY_TYPE / CAPABILITY_DEF line declares: shared by every definition built from it.
/datum/capability_info
	var/cap_id
	/// The definition's type.
	var/cap_type
	/// The name of the param that is the selector, or null when key = NONE.
	var/key_param
	/// The prefix of the ops the capability brings ("cover" for cover.open): the constructor's name, or prefix = of the declaration.
	var/name
	/// stacks =: list("stack"), list("unique") or list("best", "param").
	var/list/stacks
	/// The declared parameter names, in order.
	var/list/param_names

/// Registration rows of the CAPABILITY_TYPE / CAPABILITY_DEF macros: list(cap_id, type, key, stacks, name, param names text).
/datum/capdef_decl/proc/spec()
	return null

// cap_id -> /datum/capability_info, and whether the declarations were read. UNMANAGED globals: no initializer runs for them, so nothing resets
// them after the fact. A type's table can first build while the globals are still being made (the intercom global does), and a managed
// global's initializer ran after that build, wiping what it had read; the registry is created on first use instead.
GLOBAL_RAW(/list/capability_infos)
GLOBAL_UNMANAGED(capability_infos)
GLOBAL_RAW(/capability_infos_built)
GLOBAL_UNMANAGED(capability_infos_built)

/// The info record of capability `cap_id`, from the declarations (built on first use). null when nothing declared it.
/proc/capability_info(cap_id)
	RETURN_TYPE(/datum/capability_info)
	if(!GLOB.capability_infos_built)
		capability_infos_build()
	return GLOB.capability_infos["[cap_id]"]

/// The info record of the definition type `cap_type` (granted(E, /datum/e0_cap/phased) names a type, not an id).
/proc/capability_info_of_type(cap_type)
	RETURN_TYPE(/datum/capability_info)
	if(!GLOB.capability_infos_built)
		capability_infos_build()
	for(var/id in GLOB.capability_infos)
		var/datum/capability_info/info = GLOB.capability_infos[id]
		if(info.cap_type == cap_type)
			return info
	return null

/proc/capability_infos_build()
	GLOB.capability_infos_built = TRUE
	var/list/registry = GLOB.capability_infos = list()
	for(var/decl_type in subtypesof(/datum/capdef_decl))
		var/datum/capdef_decl/D = new decl_type
		var/list/row = D.spec()
		if(!length(row))
			continue
		var/datum/capability_info/info = new
		info.cap_id = row[1]
		info.cap_type = row[2]
		var/key_option = row[3]
		info.key_param = (isnull(key_option) || key_option == NONE) ? null : "[key_option]"
		info.stacks = row[4] || list(STACKS_STACK)
		info.name = row[5]
		info.param_names = list()
		for(var/part in splittext(row[6], ","))
			var/param_name = trim(part)
			if(length(param_name))
				info.param_names += param_name
		var/datum/capability/probe = new info.cap_type
		for(var/param_name in info.param_names)
			if(!(param_name in probe.vars) || cap_reserved_var(param_name))
				declare_report("capability [info.name] ([info.cap_type]): param '[param_name]' is no var of the definition datum -- the params are vars on it, with their defaults")
		if(info.key_param && !(info.key_param in info.param_names))
			declare_report("capability [info.name]: key = \"[info.key_param]\" is not one of its params")
		qdel(probe) // ALLOW(lifecycle): a probe instance made only to read a type's declarations
		if(registry["[info.cap_id]"])
			var/datum/capability_info/known = registry["[info.cap_id]"]
			declare_report("capability id [info.cap_id] is declared twice: [known.cap_type] and [info.cap_type]")
			continue
		registry["[info.cap_id]"] = info

/**
 * Builds the definition `cap_type` for a constructor call and interns it. `values` is the call's parameters in declaration order (a param
 * left out is null and keeps the datum's default); `names_text` is the declared parameter names, "label, power".
 */
/proc/cap_construct(cap_id, cap_type, list/values, names_text)
	RETURN_TYPE(/datum/capability)
	var/datum/capability_info/info = capability_info(cap_id)
	if(!info)
		var/message = "capability id [cap_id] ([cap_type]) was built by a constructor but no CAPABILITY_TYPE / CAPABILITY_DEF declares it"
		declare_report(message)
		CRASH(message) // a capability that cannot resolve must never be dropped silently from a table
	var/datum/capability/def = new cap_type
	def.cap_id = cap_id
	var/list/ctor = list()
	for(var/i in 1 to length(info.param_names))
		if(i <= length(values) && !isnull(values[i]))
			ctor[info.param_names[i]] = values[i]
	return cap_build(def, info, ctor)

/// Vars of /datum/capability that are the engine's or the legacy form's, never a param.
/proc/cap_reserved_var(name)
	return (name in list("cap_id", "selector", "params", "ctor", "key", "type", "vars", "parent_type", "tag", "datum_flags", "gc_destroyed", "rx", "om_rec", "own_holder_ref", "own_slot", "own_key_text", "own_holder_type", "layer_name", "layer_order", "examine_order", "draws_var", "joins", "data_type", "cadence", "destroy_phase", "holder_hooks"))

/// Applies the params of `ctor` to a fresh definition, fixes its selector and key, and interns it.
/proc/cap_build(datum/capability/def, datum/capability_info/info, list/ctor)
	for(var/name in ctor)
		if((name in def.vars) && !cap_reserved_var(name))
			def.vars[name] = ctor[name] // ALLOW(api): a capability constructor sets its params, which are vars, by declared name
	def.ctor = length(ctor) ? ctor : null
	if(info.key_param)
		var/selector = cap_param(def, info.key_param)
		def.selector = isnull(selector) ? null : "[selector]"
	def.key = "[def.cap_id]" + (def.selector ? ":[def.selector]" : "")
	return cap_intern(def)

/// The value of a definition's param.
/proc/cap_param(datum/capability/def, name)
	if(name in def.vars)
		return def.vars[name]
	return null

/// The definition with the params of `changes` (the non-null params of a constructor call) applied over `def`'s own: rebuilt and interned.
/// `variant` swaps the datum type and keeps the params.
/proc/cap_reconfigured(datum/capability/def, list/changes, variant = null)
	var/datum/capability_info/info = capability_info(def.cap_id)
	if(!info)
		return def
	var/new_type = variant || def.type
	var/datum/capability/copy = new new_type
	copy.cap_id = def.cap_id
	var/list/ctor = def.ctor ? def.ctor.Copy() : list()
	def.carry_over(copy)
	copy.reconfigure_ctor(ctor, changes)
	return cap_build(copy, info, ctor)

/// configure(): writes the params `changes` names into `ctor` (the inherited params). The default replaces each; a capability whose
/// param accumulates down the tree (reagents()' `add`) merges it here instead.
/datum/capability/proc/reconfigure_ctor(list/ctor, list/changes)
	for(var/name in changes)
		ctor[name] = changes[name]

/// A definition rebuilt by configure() keeps what its params do not carry (a graph capability's compiled graph).
/datum/capability/proc/carry_over(datum/capability/copy)
	return

/// The entries the definition brings: ops, contributions, hooks, look layers, relations. The default has none; a CAPABILITY_TYPE
/// datum overrides it (re-run on configure), a CAPABILITY_DEF body is `/datum/capability/def/<name>/entries()`.
/datum/capability/proc/entries()
	RETURN_TYPE(/list)
	return null

/// Base of the datums a CAPABILITY_DEF body hangs its entries() on.
/datum/capability/def

/// A short text of a definition's params, for explain output: "reflect_chance=45".
/proc/cap_params_text(datum/capability/def)
	var/list/parts = list()
	for(var/name in def.ctor)
		parts += "[name]=[def.ctor[name]]"
	return jointext(parts, ", ")

/// Stacking policy of a definition: list("stack"), list("unique") or list("best", param).
/proc/cap_stacks(datum/capability/def)
	var/datum/capability_info/info = def.cap_id ? capability_info(def.cap_id) : null
	return info ? info.stacks : list(STACKS_STACK)

/**
 * Capability state keys (section 4 "Capability state: cap_keys", section 11). cap_keys(CAP_X, OPEN = MSG(cover/closed), ...) registers
 * the keys of one capability in order, bit 1 first, at most 24; each key is a boolean the capability's ops set. The id of a key is
 * CAPKEY_ID(cap, bit), written as a #define beside the declaration until the generator emits it.
 */

/datum/cap_keys_decl/proc/spec()
	return null

// cap_id -> list(name -> bit), key id -> reason (a /datum/msg type), and whether they were read: unmanaged, built on first use (see capability_infos).
GLOBAL_RAW(/list/cap_key_defs)
GLOBAL_UNMANAGED(cap_key_defs)
GLOBAL_RAW(/list/cap_key_reasons)
GLOBAL_UNMANAGED(cap_key_reasons)
GLOBAL_RAW(/cap_keys_built)
GLOBAL_UNMANAGED(cap_keys_built)

/// The reason (a /datum/msg type) of state key id `key`, or null.
/proc/cap_key_reason(key)
	if(!GLOB.cap_keys_built)
		cap_keys_build()
	return GLOB.cap_key_reasons["[key]"]

/proc/cap_keys_build()
	GLOB.cap_keys_built = TRUE
	GLOB.cap_key_defs = list()
	GLOB.cap_key_reasons = list()
	for(var/decl_type in subtypesof(/datum/cap_keys_decl))
		var/datum/cap_keys_decl/D = new decl_type
		var/list/row = D.spec()
		if(!length(row))
			continue
		var/cap_id = row[1]
		var/list/keys = row[2]
		if(length(keys) > 24)
			declare_report("capability [cap_id] declares [length(keys)] state keys: a word holds at most 24")
		var/bit = 0
		var/list/names = list()
		for(var/name in keys)
			bit++
			names[name] = bit
			GLOB.cap_key_reasons["[CAPKEY_ID(cap_id, bit)]"] = keys[name]
		GLOB.cap_key_defs["[cap_id]"] = names

/// The bit (1 to 24) of state key `name` of capability `cap_id`, or 0.
/proc/cap_key_bit(cap_id, name)
	if(!GLOB.cap_keys_built)
		cap_keys_build()
	var/list/names = GLOB.cap_key_defs["[cap_id]"]
	return names ? names[name] : 0
