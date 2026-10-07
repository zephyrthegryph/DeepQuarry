// The op compiler (doc/rewrite/final_api.html, section 9 "Extend targets, overrides and precedence"; section 19 "E2, parts").
//
// An op is declared as an entry (op(key, parts...)); everything that changes it is declared beside it (extend, without, configure of
// E1's table builder). The compiler folds an op and everything addressed to it into ONE /datum/op_plan, by the combine rules of
// section 9: requirements accumulate, single values (wait, cooldown, priority, says, plays, verbs, label) replace and the most specific
// declaration wins, effects append, tags accumulate, costs combine per resource.
//
// Precedence, lowest to highest: library defaults (the tool profile), the op's own parts, group extends (CAP_X, TAG_X; same level, in
// list order), then extend("key"). A subtype beats its parent at each level because the table lists parents first.
//
// A plan is compiled once per compiled type table (and once per interned capability definition for a capability granted at runtime) and
// cached: resolution reads plans, never entries. Compile errors are reported at table build through table_error() with the file:line of
// the declaration, so an author sees them at boot and a test build fails on them.

/// The precedence levels a part is folded in at.
#define PLAN_LEVEL_DEFAULT 0
#define PLAN_LEVEL_OWN 1
#define PLAN_LEVEL_GROUP 2
#define PLAN_LEVEL_KEY 3

/// One compiled op. Immutable after build, shared by every instance of the type; never write one.
/datum/op_plan
	var/key
	/// The key as the op declared it, without the capability's prefix (a window action may name it that way).
	var/base_key
	/// "file:line" of the op's declaration (kept in every build).
	var/origin
	/// The key of the capability that brought the op, or null for a type's own.
	var/owner
	/// The capability definition that brought it, or null.
	var/datum/capability/owner_def
	/// Position among the type's ops: the last tie-break (declaration order).
	var/seq = 0
	/// /datum/entry/part/bind, in declaration order.
	var/list/bindings
	/// Select columns: "origin", "reach", "by", "authority", "gesture", "presents" -> value; "answers" -> list; "stance" -> list.
	var/list/selects
	/// Match conditions: every one must hold.
	var/list/conds
	/// Requirements, in order (new /datum/entry/part/req, or a legacy /datum/req that has a new form).
	var/list/needs
	/// The space an at(SPACE_X) places the op in, or null (code/engine/library/spaces.dm).
	var/space
	/// The Wait workflow in declaration order: /datum/entry/part/wait and /datum/entry/part/asks.
	var/list/steps
	/// resource id -> amount, from costs(); cost_order keeps declaration order.
	var/list/costs
	var/list/cost_order
	/// A cooldown(t) in deciseconds, or null.
	var/cooldown_t
	var/consumes = FALSE
	/// The captured fields: name -> resume policy.
	var/list/captured
	var/list/chance_entry
	var/datum/entry/part/chance/chance
	/// Effects in declaration order, the early ones (then(.., early = TRUE)) first.
	var/list/effects
	var/early_effects = 0
	var/datum/entry/part/says/says
	var/datum/entry/part/begins/begins
	var/datum/entry/part/plays/plays
	/// plays(SFX, at_start = TRUE): played when the first wait starts.
	var/datum/entry/part/plays/start_plays
	/// starts(): the handlers that run when the first wait starts.
	var/list/starts
	var/datum/entry/part/verbs/verb_pair
	var/datum/entry/part/flash/flash
	var/log_type
	var/list/delayed
	var/quiet = FALSE
	/// claims(mask): what the op holds while it waits (CLAIM_*); null when it declares none (op_derive_claims fills it from the parts at table build:
	/// hands for a wait with an item/tool/stack binding, body for a wait that keeps STAY). claims() alone is CLAIM_ALL; claims(NONE) holds nothing.
	var/claim_mask
	/// TRUE when claim_mask was derived from the parts (op_derive_claims), not written with claims().
	var/claims_derived = FALSE
	var/passes = FALSE
	/// silent_wait(): the wait draws no progress bar.
	var/silent_wait = FALSE
	/// on_interrupt(): the handler that runs when the wait is broken.
	var/interrupted
	var/label
	/// An explicit OP_PRIORITY_X, or null.
	var/priority_tier
	/// list("above"|"below", key), or null.
	var/list/priority_rel
	/// What a canonical click_order() puts this op above: list(list(input, key pattern, ...), ...), nearest first; or null.
	var/list/click_below
	var/list/tags
	/// The window action a ui_act() binding is reached by, and the arg() parts it declares.
	var/ui_action
	var/list/ui_args
	var/topic_key
	/// The href namespace of the topic() binding (null: plain hrefs).
	var/topic_namespace
	var/list/topic_args
	var/toggles = FALSE
	var/hostile = FALSE
	var/list/undone
	/// Every part folded in, as "level part @ origin": what explain_type prints.
	var/list/provenance
	/// The tier the op sits at (OP_PRIORITY_X): explicit priority, else the highest its parts yield.
	var/tier = OP_PRIORITY_NORMAL
	/// Build problems found while compiling this plan (also reported through table_error()).
	var/list/problems

/// The compiled ops of a type table, by key and in order.
/datum/op_index
	var/list/by_key
	var/list/ordered
	/// TRUE when one of the ops has a clicks() binding: its holder, as an actor, has ops its own clicks can reach.
	var/has_clicks = FALSE
	/// Topic namespace ("" for plain hrefs) -> topic key -> plan, made on first use (op_topic_table()).
	var/list/topic_plans

/datum/type_table
	/// The compiled ops of the table (made on first use), and the ones each granted capability definition would bring to a holder of it, by definition key.
	var/datum/op_index/op_index
	var/list/op_def_indexes

/// Entries (centry) of an index being built, with the extend items that address them.
/proc/op_index_build(datum/type_table/T, list/items, list/extends, report = TRUE)
	RETURN_TYPE(/datum/op_index)
	var/datum/op_index/index = new
	index.by_key = list()
	index.ordered = list()
	var/seq = 0
	for(var/datum/centry/C as anything in items)
		var/datum/entry/E = C.item
		if(!istype(E) || E.kind != ENTRY_OP)
			continue
		seq++
		var/datum/op_plan/P = op_plan_build(T, C, E, extends, seq, report)
		if(!P)
			continue
		if(index.by_key[P.key])
			// A later declaration of a key replaces the earlier one at the same level (a subtype's own op beats its parent's).
			index.ordered -= index.by_key[P.key]
		index.by_key[P.key] = P // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
		index.ordered += P // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	for(var/datum/op_plan/clicked as anything in index.ordered)
		for(var/datum/entry/part/bind/B as anything in clicked.bindings)
			if(B.bind_kind == BIND_CLICKS)
				index.has_clicks = TRUE
	var/list/chains = list()
	for(var/datum/centry/C as anything in items)
		var/datum/entry/E = C.item
		if(istype(E) && E.kind == ENTRY_CLICK_ORDER)
			chains += E
	if(length(chains))
		for(var/datum/op_plan/P as anything in index.ordered)
			op_plan_take_click_orders(P, chains)
	return index

// ---- canonical click orders ----

/// click_order(input, keys...): the order ops answering one input sit in, highest first, declared ONCE by the bundle that composes them (the
/// maintenance hatch orders the construction steps, the panel, the wires, the subversion reset and the window), so a type that has them needs no
/// priority(above(...)) per op. `input` is a tool quality (TOOL_X) or BIND_HAND; only ops with a binding for that input take part. A key ending in
/// "*" names every op whose key starts with the rest ("construction.undo:*"); a list of keys is one rank (its ops are not ordered among
/// themselves). Each op sits just above the nearest lower rank the holder has. Keys the type does not have are skipped, so one order serves every
/// type the bundle is on. An op's own priority(above/below(...)) still wins over it.
/proc/click_order(input, k1, k2, k3, k4, k5, k6)
	var/list/keys = list()
	for(var/k in list(k1, k2, k3, k4, k5, k6))
		if(!isnull(k))
			keys += list(k)
	return entry_make(ENTRY_CLICK_ORDER, null, list("input" = input, "keys" = keys))

/// Does `key` match a click_order() pattern (exact, a prefix ending in "*", or a list of those: one rank)?
/proc/op_key_matches(key, pattern)
	if(islist(pattern))
		for(var/one in pattern)
			if(op_key_matches(key, one))
				return TRUE
		return FALSE
	if(copytext(pattern, -1) == "*")
		return findtext(key, copytext(pattern, 1, -1)) == 1
	return key == pattern

/// Does the op answer the click_order() input (a tool quality, or BIND_HAND)?
/proc/op_plan_takes_input(datum/op_plan/P, input)
	for(var/datum/entry/part/bind/B as anything in P.bindings)
		if(input == BIND_HAND)
			if(B.bind_kind == BIND_HAND)
				return TRUE
		else if(B.bind_kind == BIND_TOOL && (input in B.args["quality"]))
			return TRUE
	return FALSE

/// Records on P what each click order puts it above: the ranks after the first one P matches.
/proc/op_plan_take_click_orders(datum/op_plan/P, list/chains)
	for(var/datum/entry/E as anything in chains)
		var/input = E.args["input"]
		if(!op_plan_takes_input(P, input))
			continue
		var/list/keys = E.args["keys"]
		for(var/i in 1 to length(keys))
			if(!op_key_matches(P.key, keys[i]))
				continue
			if(i < length(keys))
				LAZYADD(P.click_below, list(list(input) + keys.Copy(i + 1)))
			break

/// Does a click order of A put A above B?
/proc/op_plans_click_ordered(datum/op_plan/A, datum/op_plan/B)
	for(var/list/chain as anything in A.click_below)
		if(!op_plan_takes_input(B, chain[1]))
			continue
		for(var/i in 2 to length(chain))
			if(op_key_matches(B.key, chain[i]))
				return TRUE
	return FALSE

/// The compiled ops of a type table.
/proc/op_index_of_table(datum/type_table/T)
	RETURN_TYPE(/datum/op_index)
	if(T.op_index)
		return T.op_index
	var/list/extends = list()
	for(var/datum/centry/C as anything in T.items)
		var/datum/entry/E = C.item
		if(istype(E) && E.kind == ENTRY_EXTEND)
			extends += C
	T.op_index = op_index_build(T, T.items, extends) // ALLOW(ownership): the compiled index belongs to its table: it is dropped with it
	return T.op_index

/// The compiled ops a capability definition brings when it is granted to a holder of table T (T's extends reach them by key, CAP_X and tag).
/proc/op_index_of_def(datum/type_table/T, datum/capability/def)
	RETURN_TYPE(/datum/op_index)
	var/datum/op_index/known = T.op_def_indexes?[def.key]
	if(known)
		return known
	var/list/items = activation_plan(def)
	var/list/extends = list()
	for(var/datum/centry/C as anything in items)
		var/datum/entry/E = C.item
		if(istype(E) && E.kind == ENTRY_EXTEND)
			extends += C
	for(var/datum/centry/C as anything in T.items)
		var/datum/entry/E = C.item
		if(istype(E) && E.kind == ENTRY_EXTEND)
			extends += C
	known = op_index_build(T, items, extends)
	LAZYSET(T.op_def_indexes, def.key, known) // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	return known

/// Is `C` (an extend item) addressed to the op `key` brought by capability `owner_def` with tags `tag_list`? level: group or key.
/proc/op_extend_level(datum/entry/E, key, datum/capability/owner_def, list/tag_list)
	var/target = E.args["target"]
	if(istext(target))
		return target == key ? PLAN_LEVEL_KEY : null
	if(islist(target))
		return (key in target) ? PLAN_LEVEL_KEY : null
	if(isnum(target))
		if(target >= TAG_BASE)
			return (target in tag_list) ? PLAN_LEVEL_GROUP : null
		return (owner_def && owner_def.cap_id == target) ? PLAN_LEVEL_GROUP : null
	return null

/// Reports a problem of op `key` on `T` and keeps it on the plan.
/proc/op_problem(datum/type_table/T, datum/op_plan/P, report, rule, message, hint)
	LAZYADD(P.problems, "[rule] [message]")
	if(report && T)
		table_error(T, P.origin, declare_rule(rule), "op \"[P.key]\": [message]", hint)

/// Compiles one op entry and everything addressed to it into a plan.
/proc/op_plan_build(datum/type_table/T, datum/centry/C, datum/entry/E, list/extends, seq, report)
	RETURN_TYPE(/datum/op_plan)
	var/datum/op_plan/P = new
	P.key = C.eff_key || E.key
	P.base_key = E.key
	P.origin = C.origin
	P.owner = C.owner
	P.seq = seq
	if(C.owner && T)
		var/datum/capability/owner_def = T.caps[C.owner]
		P.owner_def = owner_def
	// the op's own parts
	var/list/own = op_flatten_parts(E.children)
	var/list/tool_qualities = list()
	for(var/datum/entry/part/bind/B in own)
		if(B.bind_kind == BIND_TOOL)
			for(var/quality in B.args["quality"])
				tool_qualities |= quality
	for(var/datum/entry/part/inputs/I in own)
		for(var/datum/entry/part/bind/B in I.children)
			if(B.bind_kind == BIND_TOOL)
				for(var/quality in B.args["quality"])
					tool_qualities |= quality
	// level 0: the tool profile of the tool bindings
	for(var/quality in tool_qualities)
		op_plan_fold(T, P, tool_profile_parts(quality), PLAN_LEVEL_DEFAULT, "tool profile", report)
	// level 1: the op's own parts, checked for an effect written above an asks()
	op_plan_check_order(T, P, own, report)
	op_plan_fold(T, P, own, PLAN_LEVEL_OWN, C.origin, report)
	P.tags = P.tags || list()
	if(P.ui_action || length(P.ui_args) || op_plan_has_binding(P, BIND_UI))
		P.tags |= TAG_UI
	if(op_plan_has_binding(P, BIND_TOPIC))
		P.tags |= TAG_TOPIC
	// levels 2 and 3: extends
	var/list/group_hits = list()
	var/list/key_hits = list()
	for(var/datum/centry/XC as anything in extends)
		var/datum/entry/XE = XC.item
		var/level = op_extend_level(XE, P.key, P.owner_def, P.tags)
		if(isnull(level))
			continue
		if(level == PLAN_LEVEL_GROUP)
			group_hits += XC
		else
			key_hits += XC
	for(var/datum/centry/XC as anything in group_hits + key_hits)
		var/datum/entry/XE = XC.item
		var/drop = XE.args["drop"]
		op_plan_fold(T, P, op_flatten_parts(XE.children), PLAN_LEVEL_GROUP, XC.origin, report)
		if(drop)
			var/removed = FALSE
			for(var/requirement in P.needs.Copy())
				if(op_req_id(requirement) == drop)
					P.needs -= requirement
					removed = TRUE
			if(!removed)
				op_problem(T, P, report, RULE_OP_PART, "extend(\"[P.key]\", drop = \"[drop]\") names a requirement the op does not have", "declare the requirement with id = \"[drop]\"")
	op_plan_finish(T, P, report)
	return P

/// Flattens nested lists (bundles) and returns only entries.
/proc/op_flatten_parts(list/children)
	. = list()
	for(var/part in entry_flatten(children))
		. += part

/proc/op_plan_has_binding(datum/op_plan/P, bind_kind)
	for(var/datum/entry/part/bind/B as anything in P.bindings)
		if(B.bind_kind == bind_kind)
			return TRUE
	return FALSE

/// An effect written above an asks() is a build error: nothing irreversible happens before the last answer.
/proc/op_plan_check_order(datum/type_table/T, datum/op_plan/P, list/parts, report)
	var/seen_effect = null
	for(var/part in parts)
		if(istype(part, /datum/entry/part/effect) && !seen_effect)
			var/datum/entry/part/effect/F = part
			seen_effect = F.part_name
		else if(istype(part, /datum/entry) && !istype(part, /datum/entry/part) && !seen_effect)
			var/datum/entry/E = part
			if(E.kind == ENTRY_THEN)
				seen_effect = "then"
		else if(istype(part, /datum/entry/part/asks) && seen_effect)
			var/datum/entry/part/asks/Q = part
			op_problem(T, P, report, RULE_OP_ORDER, "[seen_effect]() is written above [Q.part_name]()", "an effect runs after the last answer: write the asks() or confirms() first (nothing irreversible happens before it)")
			return

/// Folds `parts` into the plan at `level`.
/proc/op_plan_fold(datum/type_table/T, datum/op_plan/P, list/parts, level, origin_text, report)
	for(var/part in entry_flatten(parts))
		if(istype(part, /datum/entry/part))
			var/datum/entry/part/Q = part
			LAZYADD(P.provenance, "[level] [Q.describe()] @ [origin_text]")
			Q.compile(P, level)
		else if(istype(part, /datum/entry))
			var/datum/entry/E = part
			if(E.kind == ENTRY_THEN)
				// E4's then(): the op's custom effect.
				var/datum/entry/part/effect/then/then_part = part_make(/datum/entry/part/effect/then, list("handler" = E.args["handler"], "checks" = E.args["checks"], "early" = E.args["early"]))
				LAZYADD(P.provenance, "[level] [then_part.describe()] @ [origin_text]")
				then_part.compile(P, level)
			else if(E.kind == ENTRY_CHANCE)
				// E4's chance(): the roll after the last answer and the reservation, with the failed roll's feedback as its children.
				var/datum/entry/part/chance/CH = part_make(/datum/entry/part/chance, list("percent" = E.args["percent"]), E.children)
				LAZYADD(P.provenance, "[level] [CH.describe()] @ [origin_text]")
				CH.compile(P, level)
			else if(E.kind == ENTRY_WHEN)
				if(length(E.children))
					op_problem(T, P, report, RULE_OP_PART, "a when() that wraps parts inside an op is not supported", "give the op a when(cond) part, or wrap whole ops: when(cond, op(...))")
				else
					LAZYADD(P.conds, list(E.args["cond"]))
			else if(E.kind == "graph_at")
				P.space = E.args["space"]
			else
				op_problem(T, P, report, RULE_OP_PART, "[E.kind] is not an op part", "an op holds the constructors of code/engine/parts/part.dm")
		else if(!isnull(part))
			op_problem(T, P, report, RULE_OP_PART, "[part] is not an op part", "an op holds the constructors of code/engine/parts/part.dm")

/// After every layer is folded: derive the tier, check what only the whole plan can say.
/proc/op_plan_finish(datum/type_table/T, datum/op_plan/P, report)
	if(!length(P.bindings))
		// An op with no binding is reached by key only (a state-graph edge's stand-in, a fixture's placeholder).
		P.bindings = P.bindings || list()
	for(var/datum/entry/part/bind/B as anything in P.bindings)
		if(B.bind_kind == BIND_UI)
			P.ui_action = P.ui_action || B.args["action"] || P.key
		if(B.bind_kind == BIND_TOPIC)
			P.topic_key = B.args["key"]
			P.topic_namespace = B.args["namespace"]
	// Tier: an explicit priority, else the highest tier the parts yield.
	if(!isnull(P.priority_tier))
		P.tier = P.priority_tier
	else
		var/tier = OP_PRIORITY_NORMAL
		if(P.hostile)
			tier = max(tier, OP_PRIORITY_ATTACK)
		for(var/datum/entry/part/bind/B as anything in P.bindings)
			tier = max(tier, B.yielded_tier())
		for(var/datum/entry/part/effect/F as anything in P.effects)
			tier = max(tier, F.yielded_tier())
		P.tier = tier
	op_derive_claims(P)
	if(length(P.captured) && !length(P.steps))
		op_problem(T, P, report, RULE_OP_PART, "captures() on an op with no wait(), asks() or confirms()", "captures() snapshots fields when the op first suspends at a workflow step: an op without one has nothing to capture")
	for(var/requirement in P.needs)
		var/datum/entry/part/req/R = requirement
		if(istype(R))
			var/problem = R.build_problem()
			if(problem)
				op_problem(T, P, report, RULE_OP_PART, problem, "give the requirement because = MSG(x), or a library requirement that carries a reason")
		else if(istype(requirement, /datum/req) && !op_legacy_req_has_form(requirement))
			var/datum/req/legacy = requirement
			op_problem(T, P, report, RULE_OP_PART, "the legacy requirement [legacy.type] has no form in the new engine", "write the requirement with the req_* constructors of code/engine/parts/cond.dm")

/// Does a legacy requirement class implement holds() for the new engine?
/proc/op_legacy_req_has_form(datum/req/R)
	var/static/list/known = list()
	var/found = known["[R.type]"]
	if(!isnull(found))
		return found
	// A class has a form when its own holds() is not the base one: the base is the proc declared on /datum/req itself.
	found = (R.type == /datum/req) ? FALSE : !!(R.type in GLOB.OP_LEGACY_REQ_FORMS)
	known["[R.type]"] = found
	return found

GLOBAL_LIST_INIT(OP_LEGACY_REQ_FORMS, list(/datum/req/empty_hand, /datum/req/self_held, /datum/req/access, /datum/req/stance, /datum/req/heard, /datum/req/of_type))

/// What an effect or a binding yields to the op's tier (OP_PRIORITY_X): by default nothing above normal.
/datum/entry/part/proc/yielded_tier()
	return OP_PRIORITY_NORMAL

/// A requirement's build check: text when it cannot be built, else null.
/datum/entry/part/req/proc/build_problem()
	return null

// ---- how each part folds into a plan ----

/datum/entry/part/bind/compile(datum/op_plan/P, level)
	LAZYADD(P.bindings, src) // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	if(bind_kind == BIND_UI)
		for(var/datum/entry/part/ui_arg/arg_part in children)
			LAZYADD(P.ui_args, arg_part) // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	if(bind_kind == BIND_TOPIC)
		for(var/datum/entry/part/ui_arg/arg_part2 in children)
			LAZYADD(P.topic_args, arg_part2) // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)

/datum/entry/part/inputs/compile(datum/op_plan/P, level)
	P.bindings = null
	P.ui_args = null
	P.topic_args = null
	for(var/datum/entry/part/bind/B in children)
		B.compile(P, level)

/datum/entry/part/binds/compile(datum/op_plan/P, level)
	for(var/datum/entry/part/bind/B in children)
		B.compile(P, level)

/datum/entry/part/select/compile(datum/op_plan/P, level)
	LAZYSET(P.selects, column, src.args["value"])
	if(column == "answers" && src.args["hostile"])
		P.hostile = TRUE

/datum/entry/part/needs/compile(datum/op_plan/P, level)
	for(var/requirement in children)
		LAZYADD(P.needs, requirement)

/datum/entry/part/wait/compile(datum/op_plan/P, level)
	// A wait written in a later layer replaces the one before it, in the position the earlier one held; a first one is added where it is declared.
	for(var/i in 1 to length(P.steps))
		if(istype(P.steps[i], /datum/entry/part/wait))
			P.steps[i] = src // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
			return
	LAZYADD(P.steps, src) // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)

/datum/entry/part/asks/compile(datum/op_plan/P, level)
	LAZYADD(P.steps, src) // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)

/datum/entry/part/captures/compile(datum/op_plan/P, level)
	for(var/field in src.args["fields"])
		LAZYSET(P.captured, field, src.args["resume"])

/datum/entry/part/costs/compile(datum/op_plan/P, level)
	var/id = src.args["resource"]
	var/n = src.args["n"]
	if(src.args["add"] && !isnull(LAZYACCESS(P.costs, "[id]")))
		n += P.costs["[id]"]
	LAZYSET(P.costs, "[id]", n)
	P.cost_order = P.cost_order || list()
	P.cost_order |= "[id]"

/datum/entry/part/cooldown/compile(datum/op_plan/P, level)
	P.cooldown_t = src.args["t"]

/datum/entry/part/consumes/compile(datum/op_plan/P, level)
	P.consumes = TRUE

/datum/entry/part/chance/compile(datum/op_plan/P, level)
	P.chance = src // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)

/datum/entry/part/effect/compile(datum/op_plan/P, level)
	LAZYADD(P.effects, src) // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)

/datum/entry/part/effect/then/compile(datum/op_plan/P, level)
	if(!src.args["early"])
		return ..()
	if(!P.effects)
		P.effects = list()
	P.effects.Insert(++P.early_effects, src) // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)

/datum/entry/part/effect/toggles/compile(datum/op_plan/P, level)
	..()
	P.toggles = TRUE
	// toggles(KEY, when = cond): the switch exists only while cond holds (a setting the type locks: a lasertag turret's targets), so the op is not a
	// candidate otherwise, the button does nothing and says nothing, and no handler repeats the check.
	if(!isnull(src.args["when"]))
		LAZYADD(P.conds, list(src.args["when"]))

/datum/entry/part/passes/compile(datum/op_plan/P, level)
	P.passes = TRUE

/datum/entry/part/says/compile(datum/op_plan/P, level)
	P.says = src // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)

/datum/entry/part/begins/compile(datum/op_plan/P, level)
	P.begins = src // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)

/datum/entry/part/plays/compile(datum/op_plan/P, level)
	if(src.args["at_start"])
		P.start_plays = src // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
		return
	P.plays = src // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)

/datum/entry/part/starts/compile(datum/op_plan/P, level)
	LAZYADD(P.starts, src.args["handler"])

/datum/entry/part/verbs/compile(datum/op_plan/P, level)
	P.verb_pair = src // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)

/datum/entry/part/flash/compile(datum/op_plan/P, level)
	P.flash = src // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)

/datum/entry/part/logs/compile(datum/op_plan/P, level)
	P.log_type = src.args["type"]

/datum/entry/part/delayed/compile(datum/op_plan/P, level)
	LAZYADD(P.delayed, src) // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)

/datum/entry/part/on_interrupt/compile(datum/op_plan/P, level)
	P.interrupted = src.args["handler"]

/datum/entry/part/silent_wait/compile(datum/op_plan/P, level)
	P.silent_wait = TRUE

/datum/entry/part/quiet/compile(datum/op_plan/P, level)
	P.quiet = TRUE

/datum/entry/part/claims/compile(datum/op_plan/P, level)
	P.claim_mask = isnull(src.args?["mask"]) ? CLAIM_ALL : src.args["mask"]

/datum/entry/part/label/compile(datum/op_plan/P, level)
	P.label = src.args["text"]

/datum/entry/part/priority/compile(datum/op_plan/P, level)
	var/value = src.args["value"]
	if(islist(value))
		P.priority_rel = value
	else
		P.priority_tier = value

/datum/entry/part/tag/compile(datum/op_plan/P, level)
	LAZYOR(P.tags, src.args["tag"])

/datum/entry/part/undone/compile(datum/op_plan/P, level)
	LAZYADD(P.undone, src) // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)

/// replaces(parts...): swaps the effect list for these parts (only meaningful inside an extend).
/datum/entry/part/replaces/compile(datum/op_plan/P, level)
	P.effects = null
	for(var/part in children)
		if(istype(part, /datum/entry/part/effect))
			var/datum/entry/part/effect/F = part
			F.compile(P, level)
		else if(istype(part, /datum/entry/part))
			var/datum/entry/part/Q = part
			Q.compile(P, level)

/datum/entry/part/ui_arg/compile(datum/op_plan/P, level)
	return

// yielded tiers
/datum/entry/part/bind/yielded_tier()
	switch(bind_kind)
		if(BIND_TOOL, BIND_ITEM, BIND_STACK, BIND_TK)
			return OP_PRIORITY_PART
	return OP_PRIORITY_NORMAL

/datum/entry/part/effect/put_in/yielded_tier()
	return OP_PRIORITY_PART

/datum/entry/part/effect/take_out/yielded_tier()
	return OP_PRIORITY_TAKE_OUT

/datum/entry/part/req/generic/build_problem()
	if(istext(src.args["what"]) && !src.args["because"])
		return "req(PROC_REF([src.args["what"]])) has no reason"
	return null

/datum/entry/part/req/is/build_problem()
	var/key = src.args["key"]
	if(src.args["because"])
		return null
	if(isnum(key) && key > 255 && GLOB.cap_key_reasons["[key]"] && src.args["value"] == TRUE)
		return null
	return "req_is([isnum(key) ? key : "\"[key]\""], [src.args["value"]]) has no reason"

/datum/entry/part/req/at_least/build_problem()
	return src.args["because"] ? null : "req_at_least([src.args["key"]], [src.args["n"]]) has no reason"

// ---- build-time checks that need the whole table ----

/// Compiles every op of a table (reporting each problem at table build) and checks the one rule that spans ops: two ops of a type with the same
/// input, the same intent and the same tier are a build error naming both lines.
/proc/op_validate_table(datum/type_table/T)
	var/datum/op_index/index = op_index_of_table(T)
	var/list/plans = index.ordered
	for(var/i in 1 to length(plans))
		for(var/j in i + 1 to length(plans))
			var/datum/op_plan/A = plans[i]
			var/datum/op_plan/B = plans[j]
			var/clash = op_plans_clash(A, B)
			if(clash)
				table_error(T, B.origin, declare_rule(RULE_OP_CLASH), "ops \"[A.key]\" ([A.origin]) and \"[B.key]\" take the same input ([clash]) at the same tier ([op_tier_name(A.tier)])", "give one a different input, a different tier, or passes() on the first; order them in the composing bundle's click_order(), or with priority(above(\"[A.key]\")); or make their when() parts mutually exclusive")

/// The shared input text of two ops that would answer the same input at the same tier and intent, or null.
/proc/op_plans_clash(datum/op_plan/A, datum/op_plan/B)
	if(A.tier != B.tier)
		return null
	// priority(above(key)) / priority(below(key)) orders two ops: the hint of the build error, so it must also silence it
	if((A.priority_rel && A.priority_rel[2] == B.key) || (B.priority_rel && B.priority_rel[2] == A.key))
		return null
	// so does a canonical click_order() that names both
	if(op_plans_click_ordered(A, B) || op_plans_click_ordered(B, A))
		return null
	if(op_conds_exclusive(A, B))
		return null
	// two ops that answer disjoint stances (stance(I_HELP) and stance(I_HURT): the old _AS interactions) never answer the same click
	var/list/stances_a = LAZYACCESS(A.selects, "stance")
	var/list/stances_b = LAZYACCESS(B.selects, "stance")
	if(length(stances_a) && length(stances_b) && !length(stances_a & stances_b))
		return null
	for(var/datum/entry/part/bind/BA as anything in A.bindings)
		for(var/datum/entry/part/bind/BB as anything in B.bindings)
			if(BA.bind_kind != BB.bind_kind)
				continue
			var/same_input = null
			switch(BA.bind_kind)
				if(BIND_UI)
					same_input = ((BA.args["action"] || A.key) == (BB.args["action"] || B.key)) ? "ui_act(\"[BA.args["action"] || A.key]\")" : null
				if(BIND_TOPIC)
					same_input = (BA.args["key"] == BB.args["key"]) ? "topic(\"[BA.args["key"]]\")" : null
				if(BIND_MENU, BIND_AI)
					same_input = null // chosen by key, and keys are unique
				else
					same_input = (BA.sig == BB.sig) ? BA.describe() : null
			if(!same_input)
				continue
			if(BA.bind_kind in list(BIND_UI, BIND_TOPIC))
				return same_input
			// physical bindings clash only when they answer an intent in common
			var/list/ia = op_answers(A, BA)
			var/list/ib = op_answers(B, BB)
			for(var/intent in ia)
				if(intent in ib)
					return "[same_input], intent [op_intent_name(intent)]"
	return null

/// Are two ops' when conditions mutually exclusive? (when(c) against when(cond_not(c)), req_is(K) against req_is(K, FALSE).)
/proc/op_conds_exclusive(datum/op_plan/A, datum/op_plan/B)
	for(var/cond_a in A.conds)
		for(var/cond_b in B.conds)
			if(op_cond_negates(cond_a, cond_b) || op_cond_negates(cond_b, cond_a))
				return TRUE
	return FALSE

/proc/op_cond_negates(cond_a, cond_b)
	if(islist(cond_b) && length(cond_b) == 2 && cond_b[1] == "not" && cond_b[2] == cond_a)
		return TRUE
	// req_actor_kind(T) against req_actor_kind(T, not = TRUE), or against cond_not(req_actor_kind(T)): one actor is of a kind or it is not
	if(istype(cond_a, /datum/entry/part/req/actor_kind))
		var/datum/entry/part/req/actor_kind/KA = cond_a
		if(istype(cond_b, /datum/entry/part/req/actor_kind))
			var/datum/entry/part/req/actor_kind/KB = cond_b
			return !!KA.args["not"] != !!KB.args["not"] && actor_kind_same_types(KA.args["types"], KB.args["types"])
		if(islist(cond_b) && length(cond_b) == 2 && cond_b[1] == "not" && istype(cond_b[2], /datum/entry/part/req/actor_kind))
			var/datum/entry/part/req/actor_kind/KN = cond_b[2]
			return !!KA.args["not"] == !!KN.args["not"] && actor_kind_same_types(KA.args["types"], KN.args["types"])
	if(istype(cond_a, /datum/entry/part/req/graph_at) && istype(cond_b, /datum/entry/part/req/graph_at))
		return graph_at_exclusive(cond_a, cond_b)
	if(istype(cond_a, /datum/entry/part/req/is) && istype(cond_b, /datum/entry/part/req/is))
		var/datum/entry/part/req/is/RA = cond_a
		var/datum/entry/part/req/is/RB = cond_b
		return RA.args["key"] == RB.args["key"] && !!RA.args["value"] != !!RB.args["value"]
	return FALSE

/// Do two req_actor_kind() type arguments name the same kinds (a type, or a list of them, in any order)?
/proc/actor_kind_same_types(a, b)
	if(ispath(a) || ispath(b))
		return a == b
	var/list/la = islist(a) ? a : list()
	var/list/lb = islist(b) ? b : list()
	return length(la) == length(lb) && !length(la ^ lb)

/// The claims of an op that writes no claims(), derived once when the table is built: CLAIM_HANDS when it has a wait() and works with a held item or tool
/// (an item(), tool() or stack() binding), CLAIM_BODY when a wait() keeps the actor in place (STAY), nothing for an op without a wait. An explicit
/// claims() (claims(NONE) included) is never touched.
/proc/op_derive_claims(datum/op_plan/P)
	if(!isnull(P.claim_mask))
		return
	var/mask = NONE
	for(var/datum/entry/part/wait/W in P.steps)
		if(W.args["keeps"] & STAY)
			mask |= CLAIM_BODY
		for(var/datum/entry/part/bind/B as anything in P.bindings)
			if(B.bind_kind in list(BIND_ITEM, BIND_TOOL, BIND_STACK))
				mask |= CLAIM_HANDS
	P.claim_mask = mask
	P.claims_derived = TRUE
