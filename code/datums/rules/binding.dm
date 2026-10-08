// Per-object rule state, created only when an object with rules materializes
// (rules.md §4). One binding per object holds its world watches and,
// per rule, whether the condition held at the last look.

/// This object's rule binding (owned: deleted with the object). The binding's
/// `owner` is its one-sided back view.
/datum/var/tmp/datum/rule_binding/rule_binding

CAPABILITIES(/datum)
	owns_one(nameof(rule_binding), /datum/rule_binding)


/proc/dq_rule_binding_of(datum/thing)
	var/datum/rule_binding/binding = thing?.rule_binding
	return QDELETED(binding) ? null : binding

/// ---- Lifecycle (L2) ----
/// Subscribes `A`'s rules. /atom/on_materialize() calls it. Types whose rules
/// all watch the heat node wait for their first heat body (`force` skips that).
/proc/dq_rules_on_materialize(atom/A, force = FALSE)
	var/list/rules = dq_rules_for_type(A.type)
	if(!rules || (!force && dq_rules_heat_deferred(A.type)))
		return
	if(dq_rule_binding_of(A))
		return
	var/datum/rule_binding/binding = new(A, rules)
	if(!binding.active_count())
		own_clear(A, nameof(/datum::rule_binding), OWN_DELETE)
		return
	return binding

/// `A` just got a heat body (/atom/create_heat_body()): subscribe its deferred
/// rules, or move its existing heat watches onto the body.
/proc/dq_rules_heat_body_created(atom/A)
	if(QDELETED(A) || !(A.flags & ATOM_MATERIALIZED))
		return
	// Existing bindings' node watches follow the body themselves.
	if(dq_rule_binding_of(A))
		return
	// At rest the object followed its surroundings, unwatched: a rule whose
	// condition holds now crossed while nothing watched it, so it fires.
	var/datum/rule_binding/binding = dq_rules_on_materialize(A, TRUE)
	if(binding)
		binding.fire_holding()

/// Drops `A`'s subscriptions. /atom/on_dematerialize() calls it.
/proc/dq_rules_on_dematerialize(atom/A)
	if(dq_rule_binding_of(A))
		own_clear(A, nameof(/datum::rule_binding), OWN_DELETE)

/// Evaluate `thing`'s rules now instead of at the next dispatch. For code about
/// to destroy the object (take_damage before atom_destruction), so every rule
/// that the change triggered runs first, in the order the old code ran it.
/proc/dq_rules_settle(datum/thing)
	var/datum/rule_binding/binding = dq_rule_binding_of(thing)
	binding?.evaluate()

/// The live binding of `thing` if one of its rules replaces the legacy path `flag`.
/// Objects of a rule-driven type that never materialized (sandboxed, latent)
/// have none, and keep the legacy path.
/proc/dq_rules_binding_replacing(atom/thing, flag)
	if(!RULES_REPLACE(thing.type, flag))
		return null
	var/datum/rule_binding/binding = dq_rule_binding_of(thing)
	return binding?.replaces(flag) ? binding : null

/// A DM-owned property of `thing` changed: publish its key if anything subscribed.
/proc/dq_rules_publish(datum/thing, key_kind)
	var/datum/rule_binding/binding = dq_rule_binding_of(thing)
	if(binding?.key_subs && (key_kind in binding.table.key_kinds))
		dq_rx_publish(binding, key_kind)

/// The node handle for (thing, property), created by `provider` when given.
/proc/dq_rule_node(datum/thing, property, datum/property_provider/domain/provider)
	var/datum/rule_binding/binding = dq_rule_binding_of(thing)
	if(!binding)
		return null
	. = binding.nodes ? binding.nodes[property] : null
	if(isnull(.) && provider)
		. = dq_rx_node_new(thing)
		LAZYSET(binding.nodes, property, .)

/// Most rules one binding tracks: per-rule flags are bits of one number, and
/// DM bitwise math is exact to 24 bits.
#define RULE_BINDING_MAX_RULES 24
#define RULE_BIT(i) (1 << ((i) - 1))

/// The shared binding table for a rule list. dq_rules_for_type() returns one
/// cached list per type, so every object of a type shares one table.
/proc/dq_rule_table_for(list/rules)
	var/static/list/cache = list() // ALLOW(cache): keyed by rule list identity; lists are not valid CACHED keys
	var/datum/rule_type_table/table = cache[rules]
	if(!table)
		table = new(rules)
		cache[rules] = table
	return table

/// What every binding of one rule list shares: the rules and the key kinds
/// their triggers can subscribe. Immutable after New(); never deleted.
/datum/rule_type_table
	/// Shared rule list (dq_rules_for_type()).
	var/list/rules
	var/count = 0
	/// Every key kind a trigger of these rules watches. Publishing a kind no
	/// live watch reads is a cheap no-op.
	var/list/key_kinds

/datum/rule_type_table/New(list/rules)
	..()
	src.rules = rules
	count = length(rules)
	if(count > RULE_BINDING_MAX_RULES)
		stack_trace("[count] rules share one binding table; only the first [RULE_BINDING_MAX_RULES] bind")
		count = RULE_BINDING_MAX_RULES
	for(var/i in 1 to count)
		var/datum/rule/rule = rules[i]
		for(var/datum/rule_trigger/trigger as anything in rule.triggers)
			if(trigger.kind == RULE_TRIGGER_KEY)
				LAZYOR(key_kinds, trigger.key_kind)


/// Per-object rule state. The rule list and key kinds live in the shared
/// /datum/rule_type_table; per-rule flags are bits of three numbers, and every
/// rule's watch tokens share one flat list.
/datum/rule_binding
	/// The object whose rules these are: a one-sided back view (it owns us in rule_binding).
	var/tmp/atom/owner
	/// Shared per-type table (rules, key kinds): a registered rule_type_table (implicitly shared).
	var/datum/rule_type_table/table
	/// Bit per rule: its condition held at the last look.
	var/holding = 0
	/// Bit per rule: subscribed and not done.
	var/live = 0
	/// Bit per rule: fired at least once.
	var/fired = 0
	/// Flat [rule index, token, rule index, token, ...] for every live subscription.
	var/list/tokens
	/// Per rule: hold_for rate model (RULE_HOLD_SPENT once fired this spell) and its watch token.
	/// Both null until a hold_for rule first holds.
	var/list/hold_models
	var/list/hold_tokens
	/// property -> heat node handle (the owner's heat body, while it has one).
	var/list/nodes
	/// DM-owned key kind (text) -> live subscriptions of this binding's rules to it, or null: dq_rx_on_key() and dq_rx_cancel() keep it.
	var/list/key_subs
	/// TRUE while a merged key wake is waiting for its tick.
	var/key_wake_pending = FALSE
	/// Every world watch made for this binding (dq_rx_*), deleted with it.
	/// Deleted by Destroy() (dq_rx_clear()), not by the lifecycle's owned-var pass: it is a
	/// plain list, and qdel() refuses lists.
	var/list/world_watches

/datum/rule_binding/New(atom/owner, list/rules)
	..()
	rel_set(src, nameof(owner), owner)
	table = dq_rule_table_for(rules)
	rel_set(owner, nameof(owner.rule_binding), src)
	var/count = table.count
	for(var/i in 1 to count)
		if(subscribe(i, rules[i]))
			live |= RULE_BIT(i)
	// Baseline: a rule fires on crossing, not because it already holds.
	for(var/i in 1 to count)
		if((live & RULE_BIT(i)) && check(rules[i]))
			holding |= RULE_BIT(i)

/// Phase 1 (unbind): drops its rules and frees its Rust reactor nodes.
/datum/rule_binding/lifecycle_unbind()
	. = ..()
	if(table)
		for(var/i in 1 to table.count)
			drop(i)
	for(var/property in nodes)
		dq_rx_node_free(nodes[property])
	nodes = null
	dq_rx_clear(src)

/// Shared rule list (tests and diagnostics).
/datum/rule_binding/proc/rule_list()
	return table.rules

/// Whether rule i held at the last look (tests and diagnostics).
/datum/rule_binding/proc/is_holding(i)
	return (holding & RULE_BIT(i)) ? TRUE : FALSE

/// Whether a live rule on this binding replaces the RULE_REPLACES_* `flag`.
/datum/rule_binding/proc/replaces(flag)
	var/list/rules = table.rules
	for(var/i in 1 to table.count)
		var/datum/rule/rule = rules[i]
		if((rule.replaces & flag) && (live & RULE_BIT(i)))
			return TRUE
	return FALSE

/datum/rule_binding/proc/active_count()
	. = 0
	for(var/i in 1 to table.count)
		if(live & RULE_BIT(i))
			.++

/// Subscribe rule i's triggers, adding its tokens to `tokens`. Returns FALSE,
/// subscribing nothing, if the owner can't have this rule (a threshold level
/// it doesn't have).
/datum/rule_binding/proc/subscribe(i, datum/rule/rule)
	var/list/out = list()
	for(var/datum/rule_trigger/trigger as anything in rule.triggers)
		switch(trigger.kind)
			if(RULE_TRIGGER_THRESHOLD)
				var/level = trigger.level_for(owner)
				if(isnull(level))
					cancel_all(out)
					return FALSE
				var/handle = trigger.provider().node_of(owner, TRUE)
				var/above = trigger.fires_above()
				// Watches fire at >= / <=; a strict comparison watches just past the level.
				if(trigger.op == PRED_CMP_GT)
					level += dq_rule_epsilon(level)
				else if(trigger.op == PRED_CMP_LT)
					level -= dq_rule_epsilon(level)
				out += dq_rx_when_threshold(src, handle, trigger.provider().channel, above, level, TRUE)
			if(RULE_TRIGGER_BAND)
				var/handle = trigger.provider().node_of(owner, TRUE)
				out += dq_rx_when_band(src, handle, trigger.provider().channel, list(trigger.lo, trigger.hi + dq_rule_epsilon(trigger.hi)))
			if(RULE_TRIGGER_DIFFERENCE)
				out += dq_rx_on_change(src, trigger.provider().node_of(owner, TRUE), trigger.provider().channel)
				out += dq_rx_on_change(src, trigger.provider_b().node_of(owner, TRUE), trigger.provider_b().channel)
			if(RULE_TRIGGER_KEY)
				if(trigger.is_threshold() && isnull(trigger.level_for(owner)))
					cancel_all(out)
					return FALSE
				out += dq_rx_on_key(src, trigger.key_kind)
	// A subscribed rule is live even when a watch came back null, as before.
	for(var/token in out)
		if(!tokens)
			tokens = list()
		tokens += i
		tokens += token
	return TRUE

/datum/rule_binding/proc/cancel_all(list/out)
	for(var/token in out)
		dq_rx_cancel(src, token)
	return null

/// Drop rule i's subscriptions and hold model.
/datum/rule_binding/proc/drop(i)
	if(live & RULE_BIT(i))
		live &= ~RULE_BIT(i)
		for(var/pos = length(tokens) - 1, pos >= 1, pos -= 2)
			if(tokens[pos] != i)
				continue
			var/token = tokens[pos + 1]
			tokens.Cut(pos, pos + 2)
			dq_rx_cancel(src, token)
		UNSETEMPTY(tokens)
	if(hold_models && !isnull(hold_models[i]) && hold_models[i] != RULE_HOLD_SPENT)
		om_rate_remove(hold_models[i])
		hold_models[i] = null
		hold_tokens[i] = null

/datum/rule_binding/proc/check(datum/rule/rule)
	return rule.predicate.check(null, owner, null) ? TRUE : FALSE

/// Whether the owner is still here; a binding whose owner is gone deletes itself.
/datum/rule_binding/proc/resolve()
	if(!owner || QDELETED(owner))
		spent(src)
		return FALSE
	return TRUE

/// A DM-owned key of this binding was published: one merged re-evaluation on the next tick.
/datum/rule_binding/proc/key_published(kind)
	if(key_wake_pending || !key_subs?["[kind]"])
		return
	key_wake_pending = TRUE
	after(src, 1 TICK, TYPE_PROC_REF(/datum/rule_binding, key_wake))

/datum/rule_binding/proc/key_wake()
	key_wake_pending = FALSE
	rule_wake(DQ_RX_REASON_KEY, null)

/datum/rule_binding/rule_wake(reason, source)
	if(!resolve())
		return
	evaluate()

/// Forget the baseline and evaluate: every rule whose condition holds fires.
/datum/rule_binding/proc/fire_holding()
	holding = 0
	evaluate()

/// Look at every live rule: fire on false -> true edges, run exits on true -> false.
/datum/rule_binding/proc/evaluate()
	if(!resolve())
		return
	evaluate_rules()

/datum/rule_binding/proc/evaluate_rules()
	var/list/rules = table.rules
	for(var/i in 1 to table.count)
		if(QDELETED(owner) || QDELETED(src))
			return
		var/bit = RULE_BIT(i)
		if(!(live & bit))
			continue
		var/datum/rule/rule = rules[i]
		var/now = check(rule)
		var/was = holding & bit
		if(now)
			holding |= bit
		else
			holding &= ~bit
		if(rule.hold_for)
			update_hold(i, rule, now)
			continue
		if(now && !was)
			fire(i)
		else if(!now && was && (fired & bit))
			rule.exit(owner)

/// hold_for: a rate model counts seconds held; a rate watch wakes us when it
/// reaches the hold time. It pauses while the condition doesn't hold.
/datum/rule_binding/proc/update_hold(i, datum/rule/rule, now)
	if(!hold_models)
		hold_models = new /list(table.count)
		hold_tokens = new /list(table.count)
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
		model = om_rate_linear(0, 1, 0, null)
		hold_models[i] = model
		hold_tokens[i] = dq_rx_on_rate(src, model, TRUE, rule.hold_for / 10)
		return
	// Within a tick of the hold time counts: the model reads at step ticks.
	if(now && om_rate_read(model) >= (rule.hold_for - world.tick_lag) / 10)
		om_rate_remove(model)
		hold_models[i] = RULE_HOLD_SPENT
		hold_tokens[i] = null
		fire(i)
		return
	om_rate_set_rate(model, now ? 1 : 0)
	if(now)
		// Re-arm the crossing watch from the resumed rate.
		if(!isnull(hold_tokens[i]))
			dq_rx_cancel(src, hold_tokens[i])
		hold_tokens[i] = dq_rx_on_rate(src, model, TRUE, rule.hold_for / 10)

/datum/rule_binding/proc/fire(i)
	var/list/rules = table.rules
	var/datum/rule/rule = rules[i]
	fired |= RULE_BIT(i)
	if(rule.once)
		drop(i)
	rule.fire(owner)
	if(!QDELETED(src) && !live)
		spent(src)

#undef RULE_BIT
#undef RULE_BINDING_MAX_RULES

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
				if(var_name == OP_KEY_CAP_STATE)
					capability_runtime(thing).bits = op[3]
				else
					thing.vars[var_name] = op[3] // ALLOW(api): rule effects of kind RULE_SET_VAR: the var is named by the rule table
			if(RULE_OP_SWAP)
				var/atom/movable/M = thing
				var/turf/T = get_turf(thing)
				if(istype(M))
					for(var/atom/movable/inside as anything in contents_of(M))
						inside.forceMove(T)
				var/path = op[2]
				new path(T)
				replaced_by(thing)
			if(RULE_OP_REMOVE)
				spent(thing)

