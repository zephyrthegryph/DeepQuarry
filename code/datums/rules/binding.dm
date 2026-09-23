// Per-object rule state, created only when an object with rules materializes
// (rules.md §4). One binding per object holds its reactor subscriptions and,
// per rule, whether the condition held at the last look.

/// REF(object) -> /datum/rule_binding. Keyed by text and holding the owner by
/// weakref, so a binding is no outside reference to its object (collapse).
GLOBAL_LIST_EMPTY(dq_rule_bindings)

/proc/dq_rule_binding_of(datum/thing)
	return GLOB.dq_rule_bindings[REF(thing)]

/// ---- Lifecycle (L2) ----
/// Subscribes `A`'s rules. /atom/on_materialize() calls it. Types whose rules
/// all watch the heat node wait for their first heat body (`force` skips that).
/proc/dq_rules_on_materialize(atom/A, force = FALSE)
	var/list/rules = dq_rules_for_type(A.type)
	if(!rules || (!force && dq_rules_heat_deferred(A.type)))
		return
	if(GLOB.dq_rule_bindings[REF(A)])
		return
	var/datum/rule_binding/binding = new(A, rules)
	if(!binding.active_count())
		qdel(binding)
		return
	return binding

/// `A` just got a heat body (/atom/create_heat_body()): subscribe its deferred
/// rules, or move its existing heat watches onto the body.
/proc/dq_rules_heat_body_created(atom/A)
	if(QDELETED(A) || !(A.flags & ATOM_MATERIALIZED))
		return
	if(GLOB.dq_rule_bindings[REF(A)])
		dq_rx_heat_body_created(A)
		return
	// At rest the object followed its surroundings, unwatched: a rule whose
	// condition holds now crossed while nothing watched it, so it fires.
	var/datum/rule_binding/binding = dq_rules_on_materialize(A, TRUE)
	if(binding)
		binding.fire_holding()

/// Drops `A`'s subscriptions. /atom/on_dematerialize() calls it.
/proc/dq_rules_on_dematerialize(atom/A)
	var/datum/rule_binding/binding = GLOB.dq_rule_bindings[REF(A)]
	if(binding)
		qdel(binding)

/// Evaluate `thing`'s rules now instead of at the next dispatch. For code about
/// to destroy the object (take_damage before atom_destruction), so every rule
/// that the change triggered runs first, in the order the old code ran it.
/proc/dq_rules_settle(datum/thing)
	var/datum/rule_binding/binding = GLOB.dq_rule_bindings[REF(thing)]
	binding?.evaluate()

/// The live binding of `thing` if one of its rules replaces the legacy path `flag`.
/// Objects of a rule-driven type that never materialized (sandboxed, latent)
/// have none, and keep the legacy path.
/proc/dq_rules_binding_replacing(atom/thing, flag)
	if(!RULES_REPLACE(thing.type, flag))
		return null
	var/datum/rule_binding/binding = GLOB.dq_rule_bindings[REF(thing)]
	return binding?.replaces(flag) ? binding : null

/// A DM-owned property of `thing` changed: publish its key if anything subscribed.
/proc/dq_rules_publish(datum/thing, key_kind)
	var/datum/rule_binding/binding = GLOB.dq_rule_bindings[REF(thing)]
	if(binding?.key_id && (key_kind in binding.key_kinds))
		dq_rx_publish(key_kind, binding.key_id, 1)

/// The node handle for (thing, property), created by `provider` when given.
/proc/dq_rule_node(datum/thing, property, datum/property_provider/domain/provider)
	var/datum/rule_binding/binding = GLOB.dq_rule_bindings[REF(thing)]
	if(!binding)
		return null
	. = binding.nodes ? binding.nodes[property] : null
	if(isnull(.) && provider)
		. = dq_rx_node_new(thing)
		LAZYSET(binding.nodes, property, .)

/datum/rule_binding
	var/datum/weakref/owner_ref
	/// The owner, resolved for this call. Not held between calls.
	var/tmp/atom/owner
	var/owner_key
	/// Shared rule list for the owner's type.
	var/list/rules
	/// Per rule (same index): TRUE while its condition held at the last look.
	var/list/holding
	/// Per rule: fire count.
	var/list/fired
	/// Per rule: its subscription tokens, or null once done.
	var/list/tokens
	/// Per rule: hold_for rate model (RULE_HOLD_SPENT once fired this spell) and its watch token.
	var/list/hold_models
	var/list/hold_tokens
	/// property -> heat node handle (the owner's heat body, while it has one).
	var/list/nodes
	/// Key kinds the owner must publish.
	var/list/key_kinds
	/// This binding's reactor id: the id of the owner's DM-owned keys.
	var/key_id

/datum/rule_binding/New(atom/owner, list/rules)
	..()
	owner_ref = WEAKREF(owner)
	owner_key = REF(owner)
	src.owner = owner
	src.rules = rules
	var/count = length(rules)
	holding = new /list(count)
	fired = new /list(count)
	tokens = new /list(count)
	hold_models = new /list(count)
	hold_tokens = new /list(count)
	GLOB.dq_rule_bindings[owner_key] = src
	for(var/i in 1 to count)
		tokens[i] = subscribe(rules[i])
		fired[i] = 0
	// Baseline: a rule fires on crossing, not because it already holds.
	for(var/i in 1 to count)
		if(tokens[i])
			holding[i] = check(rules[i])
	src.owner = null

/datum/rule_binding/Destroy()
	for(var/i in 1 to length(rules))
		drop(i)
	for(var/property in nodes)
		dq_rx_node_free(nodes[property])
	nodes = null
	dq_rx_clear(src)
	if(GLOB.dq_rule_bindings[owner_key] == src)
		GLOB.dq_rule_bindings -= owner_key
	owner = null
	owner_ref = null
	return ..()

/// Whether a live rule on this binding replaces the RULE_REPLACES_* `flag`.
/datum/rule_binding/proc/replaces(flag)
	for(var/i in 1 to length(rules))
		var/datum/rule/rule = rules[i]
		if((rule.replaces & flag) && tokens[i])
			return TRUE
	return FALSE

/datum/rule_binding/proc/active_count()
	. = 0
	for(var/list/rule_tokens in tokens)
		.++

/// Subscribe one rule's triggers. Returns its token list, or null if the
/// owner can't have this rule (a threshold level it doesn't have).
/datum/rule_binding/proc/subscribe(datum/rule/rule)
	var/list/out = list()
	for(var/datum/rule_trigger/trigger as anything in rule.triggers)
		switch(trigger.kind)
			if(RULE_TRIGGER_THRESHOLD)
				var/level = trigger.level_for(owner)
				if(isnull(level))
					return cancel_all(out)
				var/handle = trigger.provider.node_of(owner, TRUE)
				var/above = trigger.fires_above()
				// Watches fire at >= / <=; a strict comparison watches just past the level.
				if(trigger.op == PRED_CMP_GT)
					level += dq_rule_epsilon(level)
				else if(trigger.op == PRED_CMP_LT)
					level -= dq_rule_epsilon(level)
				out += dq_rx_when_threshold(src, handle, trigger.provider.channel, above, level, TRUE)
			if(RULE_TRIGGER_BAND)
				var/handle = trigger.provider.node_of(owner, TRUE)
				out += dq_rx_when_band(src, handle, trigger.provider.channel, list(trigger.lo, trigger.hi + dq_rule_epsilon(trigger.hi)))
			if(RULE_TRIGGER_DIFFERENCE)
				out += dq_rx_on_change(src, trigger.provider.node_of(owner, TRUE), trigger.provider.channel)
				out += dq_rx_on_change(src, trigger.provider_b.node_of(owner, TRUE), trigger.provider_b.channel)
			if(RULE_TRIGGER_KEY)
				if(trigger.is_threshold() && isnull(trigger.level_for(owner)))
					return cancel_all(out)
				if(!key_id)
					key_id = dq_rx_id(src)
				out += dq_rx_on_key(src, trigger.key_kind, key_id, 1)
				LAZYOR(key_kinds, trigger.key_kind)
	return out

/datum/rule_binding/proc/cancel_all(list/out)
	for(var/token in out)
		dq_rx_cancel(src, token)
	return null

/// Drop rule i's subscriptions and hold model.
/datum/rule_binding/proc/drop(i)
	var/list/rule_tokens = tokens[i]
	if(rule_tokens)
		cancel_all(rule_tokens)
		tokens[i] = null
	if(!isnull(hold_models[i]) && hold_models[i] != RULE_HOLD_SPENT)
		dq_rx_rate_remove(hold_models[i])
		hold_models[i] = null
		hold_tokens[i] = null

/datum/rule_binding/proc/check(datum/rule/rule)
	return rule.predicate.check(null, owner, null) ? TRUE : FALSE

/// Resolve the owner for this call; a binding whose owner is gone deletes itself.
/datum/rule_binding/proc/resolve()
	owner = owner_ref?.resolve()
	if(!owner || QDELETED(owner))
		owner = null
		qdel(src)
		return FALSE
	return TRUE

/datum/rule_binding/rule_wake(reason, source)
	if(!resolve())
		return
	evaluate()

/// Forget the baseline and evaluate: every rule whose condition holds fires.
/datum/rule_binding/proc/fire_holding()
	for(var/i in 1 to length(holding))
		holding[i] = FALSE
	evaluate()

/// Look at every live rule: fire on false -> true edges, run exits on true -> false.
/datum/rule_binding/proc/evaluate()
	if(!resolve())
		return
	evaluate_rules()
	owner = null

/datum/rule_binding/proc/evaluate_rules()
	for(var/i in 1 to length(rules))
		if(QDELETED(owner) || QDELETED(src))
			return
		if(!tokens[i])
			continue
		var/datum/rule/rule = rules[i]
		var/now = check(rule)
		var/was = holding[i]
		holding[i] = now
		if(rule.hold_for)
			update_hold(i, rule, now)
			continue
		if(now && !was)
			fire(i)
		else if(!now && was && fired[i])
			rule.exit(owner)

/// hold_for: a rate model counts seconds held; a rate watch wakes us when it
/// reaches the hold time. It pauses while the condition doesn't hold.
/datum/rule_binding/proc/update_hold(i, datum/rule/rule, now)
	var/model = hold_models[i]
	if(model == RULE_HOLD_SPENT)
		// Fired during this spell; re-arm once the condition stops holding.
		if(!now)
			hold_models[i] = null
			rule.exit(owner)
		return
	if(isnull(model))
		if(!now)
			return
		model = dq_rx_rate_linear(0, 1, 0, null)
		hold_models[i] = model
		hold_tokens[i] = dq_rx_on_rate(src, model, TRUE, rule.hold_for / 10)
		return
	// Within a tick of the hold time counts: the model reads at step ticks.
	if(now && dq_rx_rate_read(model) >= (rule.hold_for - world.tick_lag) / 10)
		dq_rx_rate_remove(model)
		hold_models[i] = RULE_HOLD_SPENT
		hold_tokens[i] = null
		fire(i)
		return
	dq_rx_rate_set_rate(model, now ? 1 : 0)
	if(now)
		// Re-arm the crossing watch from the resumed rate.
		if(!isnull(hold_tokens[i]))
			dq_rx_cancel(src, hold_tokens[i])
		hold_tokens[i] = dq_rx_on_rate(src, model, TRUE, rule.hold_for / 10)

/datum/rule_binding/proc/fire(i)
	var/datum/rule/rule = rules[i]
	fired[i]++
	if(rule.once)
		drop(i)
	rule.fire(owner)
	if(!QDELETED(src) && !active_count())
		qdel(src)

/// A small step past `level`, for strict comparisons and test inputs.
/proc/dq_rule_epsilon(level)
	return max(abs(level) * 0.0001, 0.0001)

// ---- Data transforms ----

/proc/dq_rule_apply_transform(atom/thing, list/ops)
	for(var/list/op in ops)
		if(QDELETED(thing))
			return
		switch(op[1])
			if(RULE_OP_SET)
				var/var_name = op[2]
				if(!state_is_saved(thing, var_name))
					stack_trace("rule transform sets [var_name] on [thing.type], which is not saved state")
					continue
				thing.vars[var_name] = op[3]
			if(RULE_OP_SWAP)
				var/atom/movable/M = thing
				var/turf/T = get_turf(thing)
				if(istype(M))
					for(var/atom/movable/inside as anything in M.contents)
						inside.forceMove(T)
				var/path = op[2]
				new path(T)
				qdel(thing)
			if(RULE_OP_REMOVE)
				qdel(thing)
