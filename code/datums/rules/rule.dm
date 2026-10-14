// Rules (doc/rewrite/rules.md §4): condition + effect, compiled to reactor
// subscriptions.
//
// Declaring. Subclass /datum/rule, list the types it applies to (subtypes
// inherit it; `excludes` opts subtrees out), return native unit-aware property conditions from rule_condition()
// evaluated on the holder (the object), and declare an effect:
//   effect_kind = RULE_EFFECT_DATA       transform = list(RULE_SWAP_TYPE(...), ...)
//   effect_kind = RULE_EFFECT_BEHAVIOUR  effect_proc = /obj/proc/rule_ignite
// Optional: exit_proc (runs when a fired, repeatable rule stops holding),
// hold_for (the condition must hold this long in total, e.g. "cooked"), once.
//
// Compiling. Each rule compiles its immutable declaration entries to an owned
// native simulation tree, and every property clause becomes a trigger:
//   channel-backed measure vs literal   Threshold watch   (native heat watch)
//   channel-backed vs a static property Threshold watch, level read per instance
//   channel-backed band                 Band watch        (native heat watch)
//   channel-backed vs channel-backed    change watches on both (native heat watch)
//   DM-owned property (dm_key_kind)     key subscription  (dq_rx_on_key)
// Static numeric clauses (per-type measures) are only evaluated. A rule with no
// trigger is a compile error: nothing could ever change its answer.
//
// Running. Nothing exists per instance until the object materializes and
// subscribes (dq_rules_on_materialize). Then one /datum/rule_binding per
// object holds its subscriptions. Every wake re-checks the full native condition;
// the watches only say when to look. A rule fires on the false -> true edge
// (after hold_for, which runs on a rate model and a timer, never polling).

/datum/rule
	var/name
	/// Types this rule applies to, with their subtypes.
	var/list/applies_to
	/// Subtrees of applies_to it does not apply to.
	var/list/excludes
	/// Owned compiled holder-only simulation condition.
	var/datum/simulation_condition/compiled_condition
	/// Temporary compilers are owned until compilation cleanup, including a crashing visit.
	var/datum/simulation_condition_compiler/native_compiler
	var/datum/rule_compiler/trigger_compiler
	var/effect_kind = RULE_EFFECT_BEHAVIOUR
	/// Behaviour: proc on the object, called with (rule).
	var/effect_proc
	/// Behaviour: proc on the object when a fired rule stops holding. Needs once = FALSE.
	var/exit_proc
	/// Data: list of RULE_* ops.
	var/list/transform
	/// Deciseconds the condition must hold, in total, before the effect.
	var/hold_for = 0
	/// Fire at most once per object, then drop the subscriptions.
	var/once = TRUE
	/// RULE_REPLACES_* legacy paths this rule takes over on its types.
	var/replaces = NONE
	/// Test fixtures: skipped by the type index and boot validation.
	var/test_only = FALSE
	/// Concrete types the generated threshold test instantiates; default applies_to.
	var/list/test_types
	/// Skips the generated threshold test (dq_rule_thresholds) entirely: for
	/// rules whose effect has consequences the synchronous quiet/across/further
	/// check can't safely contain on a shared test turf (a delayed explosion,
	/// a spawned singularity, ...). Compilation and boot validation still cover
	/// these rules; only the auto-instantiated firing test is skipped.
	var/skip_generated_test = FALSE
	/// Every trigger watches the object's heat node (set by compile()). An
	/// object whose rules are all heat-only subscribes when it first gets a
	/// heat body, not when it materializes: at rest it cannot cross anything.
	var/heat_only = FALSE
	// Shared parents (abstract_type == type) are skipped like test_only.
	abstract_type = /datum/rule
	/// Damage-flavour rules: the DAMAGE_BAND_* they set.
	var/band

	// Compiled
	/// /datum/rule_trigger list.
	var/list/triggers
	var/list/errors

CAPABILITIES(/datum/rule)
	owns_one(nameof(compiled_condition), /datum/simulation_condition)
	owns_one(nameof(native_compiler), /datum/simulation_condition_compiler)
	owns_one(nameof(trigger_compiler), /datum/rule_compiler)
	owns_many(nameof(triggers))

/datum/rule/proc/compile(datum/property_registry/property_registry = null)
	errors = list()
	if(!length(applies_to) && !test_only)
		errors += "applies to no types"
	switch(effect_kind)
		if(RULE_EFFECT_BEHAVIOUR)
			if(!effect_proc)
				errors += "a behaviour rule needs an effect_proc"
		if(RULE_EFFECT_DATA)
			if(!length(transform))
				errors += "a data rule needs a transform"
			for(var/list/op in transform)
				if(!(op[1] in list(RULE_OP_SET, RULE_OP_SWAP, RULE_OP_REMOVE)))
					errors += "unknown transform op [op[1]]"
		else
			errors += "unknown effect kind [effect_kind]"
	if(exit_proc && once)
		errors += "exit_proc needs once = FALSE"
	rel_clear(src, nameof(compiled_condition))
	rel_clear(src, nameof(triggers))
	var/spec = rule_condition()
	// Retire any interrupted previous compilation before acquiring new temporary owners.
	rel_clear(src, nameof(native_compiler))
	rel_clear(src, nameof(trigger_compiler))
	try
		rel_set(src, nameof(native_compiler), new /datum/simulation_condition_compiler(property_registry))
		// The returned root is owned immediately, before any validation branch.
		rel_set(src, nameof(compiled_condition), native_compiler.compile(spec))
		if(length(native_compiler.errors))
			errors += native_compiler.errors
		rel_clear(src, nameof(native_compiler))
		if(!compiled_condition && !length(errors))
			errors += "condition compiler produced no root"
		if(length(errors) || !compiled_condition)
			rel_clear(src, nameof(compiled_condition))
		else
			rel_set(src, nameof(trigger_compiler), new /datum/rule_compiler(property_registry))
			trigger_compiler.visit(compiled_condition)
			// Transfer each trigger before deleting its temporary compiler owner.
			for(var/datum/rule_trigger/trigger as anything in trigger_compiler.triggers?.Copy())
				rel_add(src, nameof(triggers), rel_take(trigger_compiler, nameof(trigger_compiler.triggers), trigger))
			errors += trigger_compiler.errors
			rel_clear(src, nameof(trigger_compiler))
			if(!length(triggers))
				errors += "has no trigger: no clause reads a channel-backed or DM-owned property"
			heat_only = length(triggers) > 0
			for(var/datum/rule_trigger/trigger as anything in triggers)
				if(trigger.kind == RULE_TRIGGER_KEY)
					heat_only = FALSE
	catch(var/exception/fault)
		rel_clear(src, nameof(native_compiler))
		rel_clear(src, nameof(trigger_compiler))
		rel_clear(src, nameof(compiled_condition))
		rel_clear(src, nameof(triggers))
		throw fault
	if(!length(errors))
		errors = null
	return !errors

/// Thresholds a generated test must cover.
/datum/rule/proc/thresholds()
	. = list()
	for(var/datum/rule_trigger/trigger as anything in triggers)
		if(trigger.is_threshold())
			. += trigger

/// Called by the binding when the rule fires on `thing`.
/datum/rule/proc/fire(atom/thing)
	dq_rule_record_fire(thing, src)
	if(effect_kind == RULE_EFFECT_BEHAVIOUR)
		call(thing, effect_proc)(src)
	else
		dq_rule_apply_transform(thing, transform)

/datum/rule/proc/exit(atom/thing)
	if(exit_proc)
		call(thing, exit_proc)(src)

// ---- Triggers ----

/datum/rule_trigger
	var/datum/property_registry/registry_static
	/// RULE_TRIGGER_*.
	var/kind
	var/property
	/// The domain provider, for channel-backed triggers.
	var/datum/property_provider/domain/provider
	/// Thresholds: SIM_COMPARE_* with NOT applied.
	var/op
	/// Literal level, or null when it comes from value_property.
	var/value
	/// A static property on the same object giving the level.
	var/value_property
	/// Bands.
	var/lo
	var/hi
	/// Difference: the second side.
	var/property_b
	var/datum/property_provider/domain/provider_b
	/// Key triggers.
	var/key_kind

/datum/rule_trigger/proc/is_threshold()
	return !isnull(op) && op != SIM_COMPARE_EQ && op != SIM_COMPARE_NE

/// Whether the condition passes above the level (for > and >=).
/datum/rule_trigger/proc/fires_above()
	return op == SIM_COMPARE_GT || op == SIM_COMPARE_GTE

/// The threshold level for `thing`, or null if it has none.
/datum/rule_trigger/proc/level_for(atom/thing)
	if(!registry_static || QDELETED(registry_static))
		return null
	return isnull(value_property) ? value : registry_static.read_value(thing, value_property)

/datum/rule_trigger/proc/describe()
	switch(kind)
		if(RULE_TRIGGER_BAND)
			return "[property] in [lo]..[hi]"
		if(RULE_TRIGGER_DIFFERENCE)
			return "[property] [op] [property_b]"
	return "[property] [op] [isnull(value_property) ? value : value_property]"

// ---- Compiler ----

/datum/rule_compiler
	var/datum/property_registry/registry_static
	var/list/triggers = list() // ALLOW(instance_list): per-rule compiler output: filled while the rule compiles and read for the rule's whole life
	var/list/errors = list() // ALLOW(instance_list): per-rule compiler output: filled while the rule compiles and read for the rule's whole life

CAPABILITIES(/datum/rule_compiler)
	owns_many(nameof(triggers))
	ref_one(nameof(registry_static), /datum/property_registry)

/datum/rule_compiler/New(datum/property_registry/property_registry = null)
	..()
	rel_set(src, nameof(registry_static), property_registry ? property_registry : dq_property_registry())

/datum/rule_compiler/proc/error(text)
	errors += "[text]"

/// The domain provider answering `id` on the rule's types, or null.
/datum/rule_compiler/proc/domain_provider(id)
	var/datum/property_provider/domain/found
	for(var/datum/property_provider/provider as anything in registry().base_providers[id])
		if(provider.source != PROP_SOURCE_DOMAIN)
			continue
		if(!istype(provider, /datum/property_provider/domain))
			error("[id] is channel-backed by [provider.type], which is not a /datum/property_provider/domain")
			return null
		found = provider
	return found

/datum/rule_compiler/proc/dm_key(id)
	var/datum/property_def/def = registry().defs[id]
	return def?.dm_key_kind

/datum/rule_compiler/proc/visit(datum/simulation_condition/node)
	if(node.kind == SIM_CONDITION_GROUP)
		for(var/datum/simulation_condition/child as anything in node.children)
			visit(child)
		return
	if(node.kind == SIM_CONDITION_MEASURE)
		var/datum/simulation_condition/cmp = node
		add_measure(cmp.property, cmp.compare, cmp.value, null)
		return
	if(node.kind == SIM_CONDITION_BAND)
		var/datum/simulation_condition/band = node
		var/datum/property_provider/domain/provider = domain_provider(band.property)
		if(provider)
			var/datum/rule_trigger/trigger = new
			rel_set(trigger, nameof(trigger.registry_static), registry())
			trigger.kind = RULE_TRIGGER_BAND
			trigger.property = band.property
			rel_set(trigger, nameof(trigger.provider), provider)
			trigger.lo = band.lo
			trigger.hi = band.hi
			rel_add(src, nameof(triggers), trigger)
		else if(dm_key(band.property))
			add_key(band.property)
		return
	if(node.kind == SIM_CONDITION_COMPARE)
		var/datum/simulation_condition/rel = node
		var/datum/property_provider/domain/a = domain_provider(rel.property)
		var/datum/property_provider/domain/b = domain_provider(rel.other_property)
		if(a && b)
			var/datum/rule_trigger/trigger = new
			rel_set(trigger, nameof(trigger.registry_static), registry())
			trigger.kind = RULE_TRIGGER_DIFFERENCE
			trigger.property = rel.property
			rel_set(trigger, nameof(trigger.provider), a)
			trigger.property_b = rel.other_property
			rel_set(trigger, nameof(trigger.provider_b), b)
			rel_add(src, nameof(triggers), trigger)
			return
		if(b || dm_key(rel.other_property))
			// Dynamic on the right: flip it so the dynamic side is on the left.
			if(a || dm_key(rel.property))
				add_key(rel.property)
				add_key(rel.other_property)
				return
			add_measure(rel.other_property, dq_rule_mirror_cmp(rel.compare), null, rel.property)
			return
		add_measure(rel.property, rel.compare, null, rel.other_property)
		return
	// Opaque simulation leaves are rejected by the engine condition compiler.


/// A comparison of `property` (op) a literal `value` or a static `value_property`.
/datum/rule_compiler/proc/add_measure(property, op, value, value_property)
	var/datum/property_provider/domain/provider = domain_provider(property)
	var/key_kind = dm_key(property)
	if(!provider && !key_kind)
		return // static
	var/datum/rule_trigger/trigger = new
	rel_set(trigger, nameof(trigger.registry_static), registry())
	trigger.kind = provider ? RULE_TRIGGER_THRESHOLD : RULE_TRIGGER_KEY
	trigger.property = property
	rel_set(trigger, nameof(trigger.provider), provider)
	trigger.op = op
	trigger.value = value
	trigger.value_property = value_property
	trigger.key_kind = key_kind
	if(value_property && (domain_provider(value_property) || dm_key(value_property)))
		error("threshold [property] against [value_property]: the level must be a static property")
	if(provider && (op == SIM_COMPARE_EQ || op == SIM_COMPARE_NE))
		error("[property] compared with == or !=; a watch needs a threshold or a band")
	rel_add(src, nameof(triggers), trigger)

/datum/rule_compiler/proc/add_key(property)
	var/key_kind = dm_key(property)
	if(!key_kind)
		return
	for(var/datum/rule_trigger/existing as anything in triggers)
		if(existing.kind == RULE_TRIGGER_KEY && existing.property == property && !existing.is_threshold())
			return
	var/datum/rule_trigger/trigger = new
	rel_set(trigger, nameof(trigger.registry_static), registry())
	trigger.kind = RULE_TRIGGER_KEY
	trigger.property = property
	trigger.key_kind = key_kind
	rel_add(src, nameof(triggers), trigger)

/// a op b  <=>  b (mirror op) a.
/proc/dq_rule_mirror_cmp(op)
	switch(op)
		if(SIM_COMPARE_GT)
			return SIM_COMPARE_LT
		if(SIM_COMPARE_GTE)
			return SIM_COMPARE_LTE
		if(SIM_COMPARE_LT)
			return SIM_COMPARE_GT
		if(SIM_COMPARE_LTE)
			return SIM_COMPARE_GTE
	return op

// ---- Registry ----

/// Every compiled rule singleton: type -> /datum/rule.
GLOBAL_TABLE(dq_rules, GLOBAL_PROC_REF(build_dq_rules))

/proc/build_dq_rules()
	var/list/rules
	rules = list()
	for(var/path in subtypesof(/datum/rule))
		var/datum/rule/rule = new path
		if(rule.test_only || rule.type == rule.abstract_type)
			continue
		if(!rule.compile())
			stack_trace("rule [path] failed to compile: [jointext(rule.errors, "; ")]")
			continue
		rules[path] = rule
	return rules

/// A compiled test-only rule singleton.
/proc/dq_rule_fixture(path)
	var/static/list/fixtures = list()
	. = fixtures[path]
	if(!.)
		var/datum/rule/rule = new path
		if(!rule.compile())
			CRASH("rule fixture [path]: [jointext(rule.errors, "; ")]")
		fixtures[path] = rule
		. = rule

/// The rules on `path`: a shared list, or null. Cached per type.
/proc/dq_rules_for_type(path)
	return CACHED(rules_for_type, path) || null

DECLARE_SHARED_CACHE(rules_for_type, GLOBAL_PROC_REF(build_rules_for_type), SC_NEVER)

/proc/build_rules_for_type(path)
	var/list/found
	var/list/rules = GLOBAL_TABLE_GET(dq_rules)
	for(var/rule_path in rules)
		var/datum/rule/rule = rules[rule_path]
		if(!dq_rule_applies(rule, path))
			continue
		LAZYADD(found, rule)
	return found || FALSE

/// Whether every rule on `path` watches only its heat node: such objects
/// subscribe when they first get a heat body (dq_rules_heat_body_created()).
/proc/dq_rules_heat_deferred(path)
	return CACHED(rules_heat_deferred, path)

DECLARE_SHARED_CACHE(rules_heat_deferred, GLOBAL_PROC_REF(build_rules_heat_deferred), SC_NEVER)

/proc/build_rules_heat_deferred(path)
	. = TRUE
	for(var/datum/rule/rule as anything in dq_rules_for_type(path))
		if(!rule.heat_only)
			. = FALSE
			break

/proc/dq_rule_applies(datum/rule/rule, path)
	for(var/root in rule.applies_to)
		if(ispath(path, root))
			for(var/excluded in rule.excludes)
				if(ispath(path, excluded))
					return FALSE
			return rule.applies_to_type(path)
	return FALSE

/// Per-type filter under applies_to, read from type vars once and cached with
/// the type index. A type it rejects has no binding and costs nothing.
/datum/rule/proc/applies_to_type(path)
	return TRUE

/// RULE_REPLACES_* flags of the rules on `path`. Cached per type.
/proc/dq_rules_replace_flags(path)
	return CACHED(rules_replace_flags, path)

DECLARE_SHARED_CACHE(rules_replace_flags, GLOBAL_PROC_REF(build_rules_replace_flags), SC_NEVER)

/proc/build_rules_replace_flags(path)
	. = NONE
	for(var/datum/rule/rule as anything in dq_rules_for_type(path))
		. |= rule.replaces

/// Boot validation: every declared rule compiles, and every applies_to is a type.
/proc/dq_rules_validate()
	. = list()
	for(var/path in subtypesof(/datum/rule))
		var/datum/rule/rule = new path
		if(rule.test_only || rule.type == rule.abstract_type)
			continue
		if(!rule.compile())
			for(var/error in rule.errors)
				. += "rule [path]: [error]"
		for(var/root in rule.applies_to)
			if(!ispath(root))
				. += "rule [path]: applies to [root], which is not a type"

// ---- Fire log (generated tests) ----

/// While a test records: "[ref]|[rule type]" -> fire count.
GLOBAL_LIST_EMPTY(dq_rule_fire_log)
GLOBAL_VAR_INIT(dq_rule_recording, FALSE)

/proc/dq_rule_record_fire(datum/thing, datum/rule/rule)
	if(GLOB.dq_rule_recording)
		var/key = "[REF(thing)]|[rule.type]"
		GLOB.dq_rule_fire_log[key] = (GLOB.dq_rule_fire_log[key] || 0) + 1

/proc/dq_rule_fire_count(datum/thing, datum/rule/rule)
	return GLOB.dq_rule_fire_log["[REF(thing)]|[rule.type]"] || 0

/// The domain provider for channel-backed triggers (a relation view).
/datum/rule_trigger/proc/provider() as /datum/property_provider/domain
	return provider

/// The second domain provider (a relation view).
/datum/rule_trigger/proc/provider_b() as /datum/property_provider/domain
	return provider_b

/// A shared definition/flyweight (implicitly shared), never cleared.
/datum/rule_compiler/proc/registry() as /datum/property_registry
	return registry_static



/datum/rule/proc/rule_condition()
	return null

CAPABILITIES(/datum/rule_trigger)
	ref_one(nameof(registry_static), /datum/property_registry)
