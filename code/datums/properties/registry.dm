// The property registry (doc/rewrite/rules.md §1).
//
// Reads:
//   PROPERTY(thing, id) / dq_property(thing, id)    instance value
//   HAS_TAG(thing, tag) / dq_has_tag(thing, tag)    instance tag
//   dq_type_property(path, id, variant)             per-type value, no instance
//   dq_type_has_tag(path, tag, variant)             per-type tag, no instance
//   dq_property_aggregate(id, things)               aggregators.dm
//
// Per-type values are computed lazily the first time a type (plus variant) is
// read, from initial() and the variant table, and never stored on instances.
// Each type's table is interned: types whose values are all equal share one
// list, so thousands of item types cost a few hundred lists.
//
// Instance reads take the base provider's instance value (saved state through
// state_adapter.dm, else the type value), then fold in contributors
// (components, equipment) with the property's aggregator.

/// The global registry, built and validated on first use. SSproperties builds
/// it at boot and reports validation errors.
/proc/dq_property_registry()
	var/static/datum/property_registry/registry
	if(!registry)
		var/list/defs = list()
		for(var/path in subtypesof(/datum/property_def))
			var/datum/property_def/def = path
			if(initial(def.id) && !initial(def.test_only))
				defs += new path
		var/list/providers = list()
		for(var/path in subtypesof(/datum/property_provider))
			var/datum/property_provider/provider = path
			if(initial(provider.property) && !initial(provider.test_only))
				providers += new path
		registry = new /datum/property_registry(defs, providers)
	return registry

/datum/property_registry
	/// id -> /datum/property_def
	var/list/defs
	/// Every provider.
	var/list/providers
	/// id -> list of base providers.
	var/list/base_providers = list()
	/// id -> list of contributors.
	var/list/contributors = list()
	/// Tag id -> bit number (0-based, across words).
	var/list/tag_bits
	/// Measure ids, sorted, in table order.
	var/list/measure_ids
	/// Validation errors found at build.
	var/list/errors
	/// "[type]" or "[type]:[variant]" -> interned per-type table.
	var/list/type_tables
	/// Canonical text -> the shared table with those values.
	var/list/interned
	/// "[type]|[id]" -> the base provider for that type, or FALSE.
	var/list/resolved_base

/datum/property_registry/New(list/def_list, list/provider_list)
	..()
	providers = provider_list
	errors = list()
	var/list/sorted_defs = sortTim(def_list.Copy(), GLOBAL_PROC_REF(cmp_property_def))
	var/tag_count = 0
	for(var/datum/property_def/def as anything in sorted_defs)
		var/datum/property_def/existing = LAZYACCESS(defs, def.id)
		if(existing)
			errors += "property [def.id] is declared twice ([existing.type] and [def.type])"
			continue
		LAZYSET(defs, def.id, def)
		base_providers[def.id] = list()
		contributors[def.id] = list()
		if(def.kind == PROP_KIND_TAG)
			LAZYSET(tag_bits, def.id, tag_count++)
		else
			LAZYADD(measure_ids, def.id)
	for(var/datum/property_provider/provider as anything in providers)
		if(!LAZYACCESS(defs, provider.property))
			continue // reported by validate()
		if(provider.is_base())
			base_providers[provider.property] += provider
		else
			contributors[provider.property] += provider
	errors += validate()

/proc/cmp_property_def(datum/property_def/a, datum/property_def/b)
	return sorttext(b.id, a.id)

// ---- Validation ----

/// Every structural check on definitions and providers. Returns error strings.
/datum/property_registry/proc/validate()
	var/list/out = list()
	var/list/units = dq_property_units()
	for(var/id in defs)
		var/datum/property_def/def = LAZYACCESS(defs, id)
		if(!dq_property_valid_aggregator(def.aggregator))
			out += "property [id] has an unknown aggregator [def.aggregator]"
		if(def.min_value > def.max_value)
			out += "property [id] has min [def.min_value] above max [def.max_value]"
		switch(def.kind)
			if(PROP_KIND_TAG)
				if(!isnull(def.unit))
					out += "tag [id] has a unit ([def.unit]); tags have none"
				if(def.aggregator != PROP_AGG_OR)
					out += "tag [id] must aggregate with OR"
			if(PROP_KIND_MEASURE)
				if(!(def.unit in units))
					out += "measure [id] has unknown unit [isnull(def.unit) ? "null" : def.unit]"
				if(def.aggregator == PROP_AGG_OR)
					out += "measure [id] cannot aggregate with OR"
			else
				out += "property [id] has unknown kind [def.kind]"
		if(!length(base_providers[id]) && !length(contributors[id]))
			out += "property [id] has no provider"
	for(var/datum/property_provider/provider as anything in providers)
		var/datum/property_def/def = LAZYACCESS(defs, provider.property)
		var/label = "[provider.type]"
		if(!def)
			out += "[label] provides unknown property [provider.property]"
			continue
		if(!(provider.source in list(PROP_SOURCE_TYPE, PROP_SOURCE_MATERIAL, PROP_SOURCE_DOMAIN, PROP_SOURCE_COMPONENT, PROP_SOURCE_EQUIPMENT)))
			out += "[label] has unknown source [provider.source]"
		if(!ispath(provider.applies_to))
			out += "[label] applies to [provider.applies_to], which is not a type"
		if(provider.unit != def.unit)
			out += "[label] yields [isnull(provider.unit) ? "no unit" : provider.unit] but [def.id] is in [isnull(def.unit) ? "no unit" : def.unit]"
		if(!provider.is_base() && def.aggregator == PROP_AGG_NONE)
			out += "[label] contributes to [def.id], which has no aggregator"
		if(provider.source == PROP_SOURCE_COMPONENT)
			var/datum/property_provider/component/comp = provider
			if(!ispath(comp.component_type, /datum/component))
				out += "[label] names [comp.component_type], which is not a component"
	// Conflicting base providers: two answering for the same types.
	for(var/id in base_providers)
		var/list/bases = base_providers[id]
		for(var/i in 1 to length(bases))
			var/datum/property_provider/a = bases[i]
			for(var/j in i + 1 to length(bases))
				var/datum/property_provider/b = bases[j]
				if(a.applies_to == b.applies_to)
					out += "[a.type] and [b.type] both provide [id] for [a.applies_to]"
				else if(ispath(b.applies_to, a.applies_to) && !(a.type in b.overrides))
					out += "[b.type] provides [id] for [b.applies_to] under [a.type] without declaring overrides"
				else if(ispath(a.applies_to, b.applies_to) && !(b.type in a.overrides))
					out += "[a.type] provides [id] for [a.applies_to] under [b.type] without declaring overrides"
	return out

/// Known PROP_UNIT_* symbols.
/proc/dq_property_units()
	var/static/list/units = list(
		PROP_UNIT_KELVIN, PROP_UNIT_JOULES, PROP_UNIT_PASCALS, PROP_UNIT_MOLES,
		PROP_UNIT_WATTS, PROP_UNIT_HEAT_CAPACITY, PROP_UNIT_KILOGRAMS,
		PROP_UNIT_CUBIC_METRES, PROP_UNIT_SIZE_CLASS, PROP_UNIT_RATIO,
	)
	return units

/// Checks one value against its definition. Returns an error string or null.
/datum/property_registry/proc/check_value(id, value)
	if(isnull(value))
		return null
	var/datum/property_def/def = LAZYACCESS(defs, id)
	if(!isnum(value))
		return "[id] = [value] is not a number"
	if(def.kind == PROP_KIND_TAG && value != TRUE && value != FALSE)
		return "tag [id] = [value] is not TRUE or FALSE"
	if(value < def.min_value || value > def.max_value)
		return "[id] = [value] is outside [def.min_value]..[def.max_value]"
	return null

// ---- Resolution ----

/// The base provider answering `id` for `path`: the deepest applies_to.
/datum/property_registry/proc/base_provider(path, id)
	var/key = "[path]|[id]"
	. = LAZYACCESS(resolved_base, key)
	if(!isnull(.))
		return . || null
	var/datum/property_provider/best
	for(var/datum/property_provider/provider as anything in base_providers[id])
		if(!ispath(path, provider.applies_to))
			continue
		if(!best || ispath(provider.applies_to, best.applies_to))
			best = provider
	LAZYSET(resolved_base, key, best || FALSE)
	return best

/// The interned per-type table for `path` and `variant`: measure id -> value,
/// plus "#tags" -> list of tag words. Shared: never mutate.
/datum/property_registry/proc/type_table(path, variant)
	var/key = isnull(variant) ? "[path]" : "[path]:[variant]"
	. = LAZYACCESS(type_tables, key)
	if(.)
		return .
	var/list/variant_vars = dq_variant_vars(path, variant)
	var/list/table = list()
	var/list/canonical = list()
	for(var/id in measure_ids)
		var/datum/property_provider/provider = base_provider(path, id)
		var/value = provider?.type_value(path, variant_vars)
		if(isnull(value))
			continue
		table[id] = value
		canonical += "[id]=[value]"
	var/list/words
	for(var/id in tag_bits)
		var/datum/property_provider/provider = base_provider(path, id)
		if(!provider?.type_value(path, variant_vars))
			continue
		var/bit = LAZYACCESS(tag_bits, id)
		var/word = round(bit / PROP_TAG_WORD_BITS) + 1
		if(!words)
			words = list()
		if(length(words) < word)
			words.len = word
		words[word] = (words[word] || 0) | (1 << (bit % PROP_TAG_WORD_BITS))
	if(words)
		table["#tags"] = words
		canonical += "#tags=[jointext(words, ",")]"
	var/canonical_text = jointext(canonical, ";")
	var/list/shared = LAZYACCESS(interned, canonical_text)
	if(!shared)
		shared = table
		LAZYSET(interned, canonical_text, shared)
	LAZYSET(type_tables, key, shared)
	return shared

// ---- Public reads ----

/// Per-type value of property `id` for `path` (and variant), with no instance.
/proc/dq_type_property(path, id, variant = null)
	var/datum/property_registry/registry = dq_property_registry()
	var/datum/property_def/def = LAZYACCESS(registry.defs, id)
	if(!def)
		CRASH("unknown property [id]")
	if(def.kind == PROP_KIND_TAG)
		return dq_type_has_tag(path, id, variant)
	return registry.type_table(path, variant)[id]

/// Whether `path` (and variant) has tag `tag`, with no instance.
/proc/dq_type_has_tag(path, tag, variant = null)
	var/datum/property_registry/registry = dq_property_registry()
	var/bit = LAZYACCESS(registry.tag_bits, tag)
	if(isnull(bit))
		CRASH("unknown tag [tag]")
	var/list/words = registry.type_table(path, variant)["#tags"]
	var/word = round(bit / PROP_TAG_WORD_BITS) + 1
	if(length(words) < word)
		return FALSE
	return (words[word] & (1 << (bit % PROP_TAG_WORD_BITS))) ? TRUE : FALSE

/// Instance value of property `id`: the base provider's value, then every
/// contributor folded in with the property's aggregator.
/proc/dq_property(datum/thing, id)
	var/datum/property_registry/registry = dq_property_registry()
	var/datum/property_def/def = LAZYACCESS(registry.defs, id)
	if(!def)
		CRASH("unknown property [id]")
	var/datum/property_provider/base = registry.base_provider(thing.type, id)
	. = base?.instance_value(thing)
	for(var/datum/property_provider/contributor as anything in registry.contributors[id])
		if(!istype(thing, contributor.applies_to))
			continue
		. = dq_property_combine(def.aggregator, ., contributor.contribute(thing))

/// Whether instance `thing` has tag `tag`.
/proc/dq_has_tag(datum/thing, tag)
	return dq_property(thing, tag) ? TRUE : FALSE
