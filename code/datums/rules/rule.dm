// Rules (doc/rewrite/rules.md §4): condition + effect, compiled to reactor
// subscriptions.
//
// Declaring. Subclass /datum/rule, list the types it applies to (subtypes
// inherit it; `excludes` opts subtrees out), give a condition as a predicate
// spec over PRED_TARGET (the object), and an effect:
//   effect_kind = RULE_EFFECT_DATA       transform = list(RULE_SWAP_TYPE(...), ...)
//   effect_kind = RULE_EFFECT_BEHAVIOUR  effect_proc = /obj/proc/rule_ignite
// Optional: exit_proc (runs when a fired, repeatable rule stops holding),
// hold_for (the condition must hold this long in total, e.g. "cooked"), once.
//
// Compiling. Each rule compiles once. Its condition compiles to a P2
// predicate, and every property clause becomes a trigger:
//   channel-backed measure vs literal   Threshold watch   (REACT_WHEN)
//   channel-backed vs a static property Threshold watch, level read per instance
//   channel-backed band                 Band watch        (REACT_WHEN)
//   channel-backed vs channel-backed    change watches on both (REACT_ON)
//   DM-owned property (dm_key_kind)     key subscription  (REACT_ON_KEY)
// Static clauses (tags, per-type measures) are only evaluated. A rule with no
// trigger is a compile error: nothing could ever change its answer.
//
// Running. Nothing exists per instance until the object materializes and
// subscribes (dq_rules_on_materialize). Then one /datum/rule_binding per
// object holds its subscriptions. Every wake re-checks the full predicate;
// the watches only say when to look. A rule fires on the false -> true edge
// (after hold_for, which runs on a rate model and a timer, never polling).

/datum/rule
	var/name
	/// Types this rule applies to, with their subtypes.
	var/list/applies_to
	/// Subtrees of applies_to it does not apply to.
	var/list/excludes
	/// Predicate spec over PRED_TARGET.
	var/list/condition
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

	// Compiled
	var/datum/predicate/predicate
	/// /datum/rule_trigger list.
	var/list/triggers
	var/list/errors

/datum/rule/proc/compile()
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
	predicate = new
	predicate.name = "rule [name || type]"
	predicate.spec = condition
	if(!predicate.compile())
		errors += predicate.errors
		predicate = null
	else
		var/datum/rule_compiler/compiler = new(src)
		compiler.visit(predicate.root)
		triggers = compiler.triggers
		errors += compiler.errors
		if(!length(triggers))
			errors += "has no trigger: no clause reads a channel-backed or DM-owned property"
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
	/// RULE_TRIGGER_*.
	var/kind
	var/property
	/// The domain provider, for channel-backed triggers.
	var/datum/property_provider/domain/provider
	/// Thresholds: PRED_CMP_* with NOT applied.
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
	return !isnull(op) && op != PRED_CMP_EQ && op != PRED_CMP_NE

/// Whether the condition passes above the level (for > and >=).
/datum/rule_trigger/proc/fires_above()
	return op == PRED_CMP_GT || op == PRED_CMP_GTE

/// The threshold level for `thing`, or null if it has none.
/datum/rule_trigger/proc/level_for(atom/thing)
	return isnull(value_property) ? value : dq_property(thing, value_property)

/datum/rule_trigger/proc/describe()
	switch(kind)
		if(RULE_TRIGGER_BAND)
			return "[property] in [lo]..[hi]"
		if(RULE_TRIGGER_DIFFERENCE)
			return "[property] [op] [property_b]"
	return "[property] [op] [isnull(value_property) ? value : value_property]"

// ---- Compiler ----

/datum/rule_compiler
	var/datum/rule/rule
	var/datum/property_registry/registry
	var/list/triggers = list()
	var/list/errors = list()

/datum/rule_compiler/New(datum/rule/rule)
	..()
	src.rule = rule
	registry = dq_property_registry()

/datum/rule_compiler/proc/error(text)
	errors += "[text]"

/// The domain provider answering `id` on the rule's types, or null.
/datum/rule_compiler/proc/domain_provider(id)
	var/datum/property_provider/domain/found
	for(var/datum/property_provider/provider as anything in registry.base_providers[id])
		if(provider.source != PROP_SOURCE_DOMAIN)
			continue
		if(!istype(provider, /datum/property_provider/domain))
			error("[id] is channel-backed by [provider.type], which is not a /datum/property_provider/domain")
			return null
		found = provider
	return found

/datum/rule_compiler/proc/dm_key(id)
	var/datum/property_def/def = registry.defs[id]
	return def?.dm_key_kind

/datum/rule_compiler/proc/visit(datum/pred_node/node)
	if(istype(node, /datum/pred_node/group))
		var/datum/pred_node/group/group = node
		for(var/datum/pred_node/child as anything in group.children)
			visit(child)
		return
	if(istype(node, /datum/pred_node/cmp))
		var/datum/pred_node/cmp/cmp = node
		if(!target_only(cmp.subject))
			return
		add_measure(cmp.property, cmp.op, cmp.value, null)
		return
	if(istype(node, /datum/pred_node/band))
		var/datum/pred_node/band/band = node
		if(!target_only(band.subject))
			return
		var/datum/property_provider/domain/provider = domain_provider(band.property)
		if(provider)
			var/datum/rule_trigger/trigger = new
			trigger.kind = RULE_TRIGGER_BAND
			trigger.property = band.property
			trigger.provider = provider
			trigger.lo = band.lo
			trigger.hi = band.hi
			triggers += trigger
		else if(dm_key(band.property))
			add_key(band.property)
		return
	if(istype(node, /datum/pred_node/rel))
		var/datum/pred_node/rel/rel = node
		if(!target_only(rel.subject) || !target_only(rel.subject_b))
			return
		var/datum/property_provider/domain/a = domain_provider(rel.property)
		var/datum/property_provider/domain/b = domain_provider(rel.property_b)
		if(a && b)
			var/datum/rule_trigger/trigger = new
			trigger.kind = RULE_TRIGGER_DIFFERENCE
			trigger.property = rel.property
			trigger.provider = a
			trigger.property_b = rel.property_b
			trigger.provider_b = b
			triggers += trigger
			return
		if(b || dm_key(rel.property_b))
			// Dynamic on the right: flip it so the dynamic side is on the left.
			if(a || dm_key(rel.property))
				add_key(rel.property)
				add_key(rel.property_b)
				return
			add_measure(rel.property_b, dq_rule_mirror_cmp(rel.op), null, rel.property)
			return
		add_measure(rel.property, rel.op, null, rel.property_b)
		return
	// Tags, tools, procs: static for a rule, evaluated on every wake.

/datum/rule_compiler/proc/target_only(subject)
	if(subject == PRED_TARGET)
		return TRUE
	error("clauses must read PRED_TARGET (the object); a rule has no actor or held item")
	return FALSE

/// A comparison of `property` (op) a literal `value` or a static `value_property`.
/datum/rule_compiler/proc/add_measure(property, op, value, value_property)
	var/datum/property_provider/domain/provider = domain_provider(property)
	var/key_kind = dm_key(property)
	if(!provider && !key_kind)
		return // static
	var/datum/rule_trigger/trigger = new
	trigger.kind = provider ? RULE_TRIGGER_THRESHOLD : RULE_TRIGGER_KEY
	trigger.property = property
	trigger.provider = provider
	trigger.op = op
	trigger.value = value
	trigger.value_property = value_property
	trigger.key_kind = key_kind
	if(value_property && (domain_provider(value_property) || dm_key(value_property)))
		error("threshold [property] against [value_property]: the level must be a static property")
	if(provider && (op == PRED_CMP_EQ || op == PRED_CMP_NE))
		error("[property] compared with == or !=; a watch needs a threshold or a band")
	triggers += trigger

/datum/rule_compiler/proc/add_key(property)
	var/key_kind = dm_key(property)
	if(!key_kind)
		return
	for(var/datum/rule_trigger/existing as anything in triggers)
		if(existing.kind == RULE_TRIGGER_KEY && existing.property == property && !existing.is_threshold())
			return
	var/datum/rule_trigger/trigger = new
	trigger.kind = RULE_TRIGGER_KEY
	trigger.property = property
	trigger.key_kind = key_kind
	triggers += trigger

/// a op b  <=>  b (mirror op) a.
/proc/dq_rule_mirror_cmp(op)
	switch(op)
		if(PRED_CMP_GT)
			return PRED_CMP_LT
		if(PRED_CMP_GTE)
			return PRED_CMP_LTE
		if(PRED_CMP_LT)
			return PRED_CMP_GT
		if(PRED_CMP_LTE)
			return PRED_CMP_GTE
	return op

// ---- Registry ----

/// Every compiled rule singleton: type -> /datum/rule.
/proc/dq_rules()
	var/static/list/rules
	if(!rules)
		rules = list()
		for(var/path in subtypesof(/datum/rule))
			var/datum/rule/rule = new path
			if(rule.test_only)
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
	var/static/list/cache = list()
	. = cache[path]
	if(!isnull(.))
		return . || null
	var/list/found
	var/list/rules = dq_rules()
	for(var/rule_path in rules)
		var/datum/rule/rule = rules[rule_path]
		if(!dq_rule_applies(rule, path))
			continue
		LAZYADD(found, rule)
	cache[path] = found || FALSE
	return found

/proc/dq_rule_applies(datum/rule/rule, path)
	for(var/root in rule.applies_to)
		if(ispath(path, root))
			for(var/excluded in rule.excludes)
				if(ispath(path, excluded))
					return FALSE
			return TRUE
	return FALSE

/// RULE_REPLACES_* flags of the rules on `path`. Cached per type.
/proc/dq_rules_replace_flags(path)
	var/static/list/cache = list()
	. = cache[path]
	if(!isnull(.))
		return .
	. = NONE
	for(var/datum/rule/rule as anything in dq_rules_for_type(path))
		. |= rule.replaces
	cache[path] = .

/// Boot validation: every declared rule compiles, and every applies_to is a type.
/proc/dq_rules_validate()
	. = list()
	for(var/path in subtypesof(/datum/rule))
		var/datum/rule/rule = new path
		if(rule.test_only)
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
