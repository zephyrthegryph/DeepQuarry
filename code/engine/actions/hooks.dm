// Hooks (doc/rewrite/final_api.html, section 10 "Hooks and events"; section 19 "E4, actions and hooks").
//
// Two forms. A BEFORE hook is an extend() of an action: needs (refuse), instead (take over), adjusts (modify one typed field). An AFTER hook is
// on_notice / on_op (react to a past-tense notice) or on_change (react to a state edge, change.dm). Nothing else is a hook.
//
//	extend(/datum/act/hit/projectile, instead(when(PROC_REF(mirror_ready)), chance(30), then(PROC_REF(reflect))))
//	extend(/datum/act/hit/projectile, adjusts(packet.amount, scale = 0.67, when = PROC_REF(shield_up)))
//	on_notice(/datum/notice/fell, then(PROC_REF(on_fell)), outcome = ACT_REPLACED)
//	on_op("cover.open", then(PROC_REF(cover_opened)))
//
// A declared entry is compiled into /datum/hook records. A type's own hooks come from its compiled table (the type-level entries), indexed once
// per table and action; hooks an activation brings (a grant, while_slotted, a species, observe()) are applied by the entry engines below onto the
// holder (rx.hooks) and die with the activation by the one teardown path. Stacking decides which activations of a capability run: a hook of a
// shadowed activation is skipped.
//
// Parts inside a hook are the Do parts of section 9. E4 owns when(), chance() and then(); every other part kind is E2's and reaches act_run_part().

/// One compiled hook.
/datum/hook
	/// HOOK_NEEDS, HOOK_INSTEAD, HOOK_ADJUSTS or HOOK_NOTICE.
	var/kind
	/// The action type the hook extends (needs, instead, adjusts) or the notice type it listens for.
	var/target
	/// The part entry (instead / adjusts / needs), or the on_notice entry.
	var/datum/entry/entry
	/// The entry of the declaration this came from (an extend or an on_notice), for removal.
	var/datum/entry/source_entry
	var/order = ORDER_NORMAL
	/// Declaration order for static hooks, attach order (past the static ones) for dynamic.
	var/serial = 0
	var/datum/activation/activation
	/// The key of the capability that brought a static hook, or null.
	var/cap_key
	/// ACT_* mask a notice hook asked for.
	var/outcomes = ACT_COMMITTED
	/// on_op: the op key the notice must carry.
	var/op_key
	/// An observe(): the handler runs on the listener (the activation's source), with A.target the observed entity.
	var/on_listener = FALSE
	/// when() blocks around a static hook (the declaration sat inside them).
	var/list/whens
	var/origin

GLOBAL_LIST_EMPTY(hook_tables) // /datum/type_table -> list of /datum/hook (every kind), built on first use
GLOBAL_LIST_EMPTY(act_plans) // /datum/type_table -> (action type -> /datum/act_plan, or FALSE for none)
GLOBAL_LIST_EMPTY(notice_plans) // /datum/type_table -> (notice type -> list of notice hooks)
GLOBAL_VAR_INIT(hook_serial, 0)

/// The hooks of one action on one entity: needs, instead, adjusts in order, and the notice hooks for its notice.
/datum/act_plan
	var/list/needs
	var/list/instead
	var/list/adjusts
	var/list/notices
	/// OR of what the notice hooks asked for.
	var/wanted = 0

// ---- constructors ----

/// instead(parts..., order = ORDER_NORMAL): the first taker in order ends the action ACT_REPLACED. Side effects allowed; when() and chance() gate it.
/proc/instead(ENTRY_SLOTS, order = ORDER_NORMAL)
	return entry_make(ENTRY_INSTEAD, null, list("order" = order), entry_flatten(ENTRY_SLOT_LIST))

/// needs(parts...): refuses the action. The requirement language is E2's; its parts reach act_needs_refusal().
/proc/hook_needs(...)
	return entry_make(ENTRY_NEEDS, null, null, entry_flatten(args.Copy()))

/// adjusts(packet.amount, by =, scale =, when =): modifies one typed field of the action before it reaches its sink. `field` is text (the
/// generator rewrites the path a declaration writes); scale applies before by.
/proc/adjusts(field, by = null, scale = null, when = null)
	return entry_make(ENTRY_ADJUSTS, null, list("field" = field, "by" = by, "scale" = scale, "when" = when))

/// adjusts_with(PROC_REF(x), when =): modifies the action in flight with code, for what a constant by/scale cannot say (a flag a listener ORs in, an amount
/// a listener splits). x(datum/act/A) runs on the hook's holder (on the listener for an observe()), may write the act's typed fields and does not take the
/// action over. An accumulator: every adjusts_with of the action runs, in order, so flags from several listeners combine.
/proc/adjusts_with(handler, when = null)
	return entry_make(ENTRY_ADJUSTS, null, list("with" = handler, "when" = when))

/// then(PROC_REF(x), checks = /datum/act/y): calls x(datum/act/A). CAP_PROC(x) names a proc of the capability datum. `checks` is an op effect's declaration of the
/// world action it starts (the op engine pre-checks it; a hook ignores it).
/// `early` (an op effect only): the effect runs before the op's other effects, in declaration order among the early ones (a shock a touch takes first).
/proc/then(handler, checks = null, early = FALSE)
	return entry_make(ENTRY_THEN, null, list("handler" = handler, "checks" = checks, "early" = early))

/// chance(p, otherwise = parts): inside an instead, takes over with probability p percent (one roll, drawn only when the hook's earlier gates held). In an
/// op the failed roll plays `otherwise` (feedback parts) and commits the op's costs.
/proc/chance(percent, list/otherwise = null)
	return entry_make(ENTRY_CHANCE, null, list("percent" = percent), entry_flatten(otherwise))

/// on_notice(/datum/notice/x, parts..., outcome = ACT_COMMITTED): reacts when the notice is delivered. The legacy form takes a handler:
/// on_notice(/datum/notice/x, PROC_REF(y)).
/proc/on_notice(type, ENTRY_SLOTS, outcome = ACT_COMMITTED, op = null)
	if(!istype(p1, /datum/entry) && !islist(p1))
		return reaction_on_notice(type, p1)
	return entry_make(ENTRY_ON_NOTICE, null, list("notice" = type, "outcome" = outcome, "op" = op), entry_flatten(ENTRY_SLOT_LIST))

/// on_op("cover.open", parts..., outcome =): sugar for on_notice(/datum/notice/op_done, parts..., op = key).
/proc/on_op(op_key, ENTRY_SLOTS, outcome = ACT_COMMITTED)
	return entry_make(ENTRY_ON_NOTICE, null, list("notice" = /datum/notice/op_done, "outcome" = outcome, "op" = op_key), entry_flatten(ENTRY_SLOT_LIST))

/// A capability of triggers only: the entries it brings are its hooks. No key of its own beyond what tells two of them apart.
/proc/hook_capability(...)
	return hook_capability_of(entry_flatten(args.Copy()), FALSE)

/datum/capability/hook
	var/list/hook_entries
	/// observe(): the handlers run on the listener.
	var/on_listener = FALSE

/datum/capability/hook/entries()
	return hook_entries

/proc/hook_capability_of(list/entries, on_listener)
	RETURN_TYPE(/datum/capability/hook)
	var/datum/capability/hook/def = new
	def.cap_id = CAP_HOOK
	def.hook_entries = entries
	def.on_listener = on_listener
	var/list/sigs = list()
	for(var/datum/entry/E in entries)
		sigs += E.sig
	def.selector = md5(jointext(sigs, ";") + (on_listener ? "L" : ""))
	def.key = "[CAP_HOOK]:[def.selector]"
	return cap_intern(def)

// ---- observe / unobserve ----

/// observe(source, /datum/notice/x, listener, parts...): `listener` hears the notice when `source` publishes it. The handlers run on the
/// listener, with A.holder the listener and A.target the source. An activation of a hook capability on `source` sourced by the listener: either
/// end dying ends it. The legacy form takes a reaction and a handler.
///
/// observe(source, /datum/act/x, listener, parts...) is the runtime counterpart of extend(/datum/act/x, parts...): the listener refuses
/// (needs), takes over (instead) or modifies in flight (adjusts, adjusts_with) an action done to `source`. The parts run on the listener
/// (A.holder is the listener for the hook, A.target the source); the activation ends with unobserve(), with the listener or with the source.
///
///	observe(host, /datum/act/injure, src, instead(when(PROC_REF(stasis_holds))))    // refuses: the injury never lands
///	observe(host, /datum/act/pre_emp, src, adjusts_with(PROC_REF(shield_emp)))      // writes A.protection in flight
/proc/observe(datum/source, trigger, datum/listener, p1, p2, p3, p4, p5, outcome = ACT_COMMITTED, op = null)
	if(!ispath(trigger))
		return legacy_observe(source, trigger, listener, p1)
	if(!source || !listener || QDELETED(source) || QDELETED(listener))
		return null
	if(!own_guard(listener, source, "an observe ([trigger])")) // the one teardown guard (code/datums/ownership/guard.dm)
		return null
	if(ispath(trigger, /datum/act/action))
		var/datum/entry/hook_entry = extend(trigger, p1, p2, p3, p4, p5)
		return grant(source, hook_capability_of(list(hook_entry), TRUE), listener)
	var/datum/entry/E = entry_make(ENTRY_ON_NOTICE, null, list("notice" = trigger, "outcome" = outcome, "op" = op), entry_flatten(list(p1, p2, p3, p4, p5)))
	return grant(source, hook_capability_of(list(E), TRUE), listener)

/// Ends what observe(source, notice, listener) made. TRUE when there was one. The legacy form takes a reaction.
/proc/unobserve(datum/source, trigger, datum/listener)
	if(!isnull(trigger) && !ispath(trigger))
		return legacy_unobserve(source, trigger, listener)
	. = 0
	for(var/datum/activation/A as anything in source?.rx?.activations?.Copy())
		if(A.dead || A.def.cap_id != CAP_HOOK || (listener && A.source != listener))
			continue
		var/datum/capability/hook/def = A.def
		if(!def.on_listener)
			continue
		var/matched = isnull(trigger)
		for(var/datum/entry/E in def.hook_entries)
			if(E.kind == ENTRY_ON_NOTICE && E.args["notice"] == trigger)
				matched = TRUE
			else if(E.kind == ENTRY_EXTEND && E.args["target"] == trigger)
				matched = TRUE
		if(matched)
			activation_end(A)
			.++

/// The observe() hooks on `source`: trigger (a notice or an action type) -> how many listeners observe it.
/proc/observer_counts(datum/source)
	. = list()
	for(var/datum/activation/A as anything in source?.rx?.activations)
		if(A.dead || A.def.cap_id != CAP_HOOK)
			continue
		var/datum/capability/hook/def = A.def
		if(!def.on_listener)
			continue
		for(var/datum/entry/E in def.hook_entries)
			var/trigger = E.kind == ENTRY_ON_NOTICE ? E.args["notice"] : E.args["target"]
			.[trigger] = (.[trigger] || 0) + 1

/// How many listeners observe `trigger` (a notice or an action type) on `source`.
/proc/observer_count(datum/source, trigger)
	var/list/counts = observer_counts(source)
	return counts[trigger] || 0

/// Ends every observe() the listener made, on anything (a state that leaves its mob, a view that is torn down). The count ended.
/proc/unobserve_all(datum/listener)
	. = 0
	for(var/datum/activation/A as anything in listener?.rx?.sourced?.Copy())
		if(A.dead || A.def.cap_id != CAP_HOOK)
			continue
		var/datum/capability/hook/def = A.def
		if(!def.on_listener)
			continue
		activation_end(A)
		.++

// ---- compiling entries into hooks ----

/// The hooks one declared entry makes (an extend's parts, an on_notice), for activation A (null for a type-level entry).
/proc/hooks_from_entry(datum/entry/E, datum/centry/C, datum/activation/A)
	. = list()
	var/serial = A ? (1000000 + A.serial * 1000 + ++GLOB.hook_serial % 1000) : ++GLOB.hook_serial
	if(E.kind == ENTRY_EXTEND)
		var/target = E.args["target"]
		if(!ispath(target, /datum/act))
			return // an op key or a capability id: E2's
		for(var/datum/entry/part in E.children)
			var/kind
			if(istype(part, /datum/entry/part/needs))
				// needs(req...) of the part engine (extend(/datum/act/insert, needs(...))): its requirements refuse the action
				var/datum/hook/needs_hook = hook_make(HOOK_NEEDS, target, part, E, C, A, serial)
				needs_hook.order = ORDER_NORMAL
				. += needs_hook
				continue
			switch(part.kind)
				if(ENTRY_INSTEAD)
					kind = HOOK_INSTEAD
				if(ENTRY_ADJUSTS)
					kind = HOOK_ADJUSTS
				if(ENTRY_NEEDS)
					kind = HOOK_NEEDS
				else
					continue
			var/datum/hook/H = hook_make(kind, target, part, E, C, A, serial)
			H.order = part.args?["order"] || ORDER_NORMAL
			. += H
		return
	if(E.kind == ENTRY_ON_CHANGE)
		. += hook_make(HOOK_CHANGE, null, E, E, C, A, serial)
		return
	if(E.kind == ENTRY_VERB)
		// A type-level verb_entry with a when = re-evaluates when its condition changes (verbs.dm).
		if(!A && !isnull(E.args["when"]) && !E.args["login"] && !E.args["hidden"])
			var/datum/entry/verb_hook = verb_entry_hook_entry(E)
			. += hook_make(HOOK_CHANGE, null, verb_hook, verb_hook, C, A, serial)
		return
	if(E.kind == ENTRY_MODES)
		// A type-level modes(var): a write of the var is picked up at the drain and the mode follows it (modes.dm).
		if(!A)
			var/datum/entry/watch = modes_watch_entry(E)
			. += hook_make(HOOK_CHANGE, null, watch, watch, C, A, serial)
		return
	if(E.kind == ENTRY_EVERY)
		// A type-level every() held by its own when = parks while the condition is false; this hook wakes it (every.dm).
		if(!A && !isnull(E.args["when"]) && !length(C.whens))
			var/datum/entry/wake = type_every_wake_entry(E)
			. += hook_make(HOOK_CHANGE, null, wake, wake, C, A, serial)
		return
	if(E.kind == ENTRY_ON_NOTICE)
		var/datum/hook/H = hook_make(HOOK_NOTICE, E.args["notice"], E, E, C, A, serial)
		H.outcomes = E.args["outcome"] || ACT_COMMITTED
		H.op_key = E.args["op"]
		. += H

/proc/hook_make(kind, target, datum/entry/entry, datum/entry/source_entry, datum/centry/C, datum/activation/A, serial)
	var/datum/hook/H = new
	H.kind = kind
	H.target = target
	H.entry = entry // ALLOW(ownership): an interned flyweight entry, never written
	H.source_entry = source_entry // ALLOW(ownership): an interned flyweight entry, never written
	H.serial = serial
	H.activation = A // ALLOW(ownership): an engine record the one teardown path drops
	if(C)
		H.cap_key = C.owner
		H.origin = C.origin
		if(!A)
			H.whens = C.whens
	if(A)
		var/datum/capability/hook/hook_def = A.def
		if(istype(hook_def))
			H.on_listener = hook_def.on_listener
	return H

/// Every type-level hook of a compiled table, in declaration order.
/proc/hook_table_of(datum/type_table/T)
	var/list/known = GLOB.hook_tables[T]
	if(!isnull(known))
		return known
	var/list/hooks = list()
	for(var/datum/centry/C as anything in T.items)
		var/datum/entry/E = C.item
		if(!istype(E) || (E.kind != ENTRY_EXTEND && E.kind != ENTRY_ON_NOTICE && E.kind != ENTRY_ON_CHANGE && E.kind != ENTRY_EVERY && E.kind != ENTRY_VERB && E.kind != ENTRY_MODES))
			continue
		hooks += hooks_from_entry(E, C, null)
	GLOB.hook_tables[T] = hooks
	return hooks

/// The notice type an action's notice is, or null for a type that is no action.
/proc/act_notice_type(act_type)
	. = GLOB.action_notice_types[act_type]
#if defined(UNIT_TESTS)
	if(!.)
		. = GLOB.action_notice_types_tests[act_type]
#endif

/// Does hook H apply to action type `act_type`?
/proc/hook_applies(datum/hook/H, act_type)
	if(H.kind == HOOK_NOTICE)
		var/notice_type = act_notice_type(act_type)
		return notice_type && ispath(notice_type, H.target)
	return ispath(act_type, H.target)

/// The static plan of an action type on a table: a /datum/act_plan, or FALSE when the table hooks nothing of it.
/proc/act_plan_static(datum/type_table/T, act_type)
	var/list/for_table = GLOB.act_plans[T]
	if(isnull(for_table))
		for_table = list()
		GLOB.act_plans[T] = for_table
	var/known = for_table[act_type]
	if(!isnull(known))
		return known
	var/datum/act_plan/P = new
	var/any = FALSE
	for(var/datum/hook/H as anything in hook_table_of(T))
		if(!hook_applies(H, act_type))
			continue
		any = TRUE
		hook_plan_add(P, H)
	if(!any)
		P = null
	for_table[act_type] = P || FALSE
	return P || FALSE

/proc/hook_plan_add(datum/act_plan/P, datum/hook/H)
	switch(H.kind)
		if(HOOK_NEEDS)
			LAZYADD(P.needs, H) // ALLOW(ownership): an engine record the one teardown path drops
		if(HOOK_INSTEAD)
			LAZYADD(P.instead, H) // ALLOW(ownership): an engine record the one teardown path drops
		if(HOOK_ADJUSTS)
			LAZYADD(P.adjusts, H) // ALLOW(ownership): an engine record the one teardown path drops
		if(HOOK_NOTICE)
			LAZYADD(P.notices, H) // ALLOW(ownership): an engine record the one teardown path drops
			P.wanted |= H.outcomes

/// TRUE when anything hooks `act_type` on holder, or listens for its notice for any outcome (so ACT_TRY must build a real act).
/proc/act_wanted(datum/holder, act_type)
	if(!islist(GLOB?.act_plans) || QDELETED(holder))
		return FALSE
	var/datum/type_table/T = table_of(holder)
	if(act_plan_static(T, act_type))
		return TRUE
	for(var/datum/hook/H as anything in holder.rx?.hooks)
		if(hook_applies(H, act_type))
			return TRUE
	var/notice_type = act_notice_type(act_type)
	return notice_type && notice_wanted(holder, notice_type, ACT_ANY)

/// The hooks that apply to `act_type` on holder now: the static plan's and the live activations', each list in order. A hook of a shadowed or
/// dead activation is left out; a static hook of a capability that has activations on the holder is represented by them.
/proc/act_plan_for(datum/holder, act_type)
	RETURN_TYPE(/datum/act_plan)
	var/datum/act_plan/P = new
	var/datum/type_table/T = table_of(holder)
	var/static_plan = act_plan_static(T, act_type)
	if(static_plan)
		var/datum/act_plan/S = static_plan
		for(var/list/L in list(S.needs, S.instead, S.adjusts, S.notices))
			for(var/datum/hook/H as anything in L)
				if(H.cap_key && hook_cap_represented(holder, H.cap_key))
					continue
				hook_plan_add(P, H)
	for(var/datum/hook/H as anything in holder.rx?.hooks)
		if(H.activation && (H.activation.dead || !H.activation.runs))
			continue
		if(hook_applies(H, act_type))
			hook_plan_add(P, H)
	P.needs = hooks_sorted(P.needs)
	P.instead = hooks_sorted(P.instead)
	P.adjusts = hooks_sorted(P.adjusts)
	P.notices = hooks_sorted(P.notices)
	return P

/// TRUE when holder has a live activation of the capability `cap_key` (the static hooks it brought are then those of the activation).
/proc/hook_cap_represented(datum/holder, cap_key)
	for(var/datum/activation/A as anything in holder.rx?.activations)
		if(!A.dead && A.def.key == cap_key)
			return TRUE
	return FALSE

/// `hooks` ordered by order, then declaration (serial). A stable insertion sort: the lists are a handful long.
/proc/hooks_sorted(list/hooks)
	if(length(hooks) < 2)
		return hooks
	var/list/out = list()
	for(var/datum/hook/H as anything in hooks)
		var/at = length(out) + 1
		for(var/i in length(out) to 1 step -1)
			var/datum/hook/other = out[i]
			if(other.order < H.order || (other.order == H.order && other.serial <= H.serial))
				break
			at = i
		out.Insert(at, H)
	return out

// ---- running parts ----

/// Calls handler (a PROC_REF text on the holder, CAP_PROC text on the capability, or a /proc path) with the context.
/proc/hook_call(datum/hook/H, handler, datum/act/A)
	var/depth = GLOB.act_depth
	var/chain_len = length(GLOB.act_chain)
	GLOB.act_depth++
	. = null
	try
		if(ispath(handler))
			. = call(handler)(A)
		else if(copytext(handler, 1, 5) == "cap:")
			. = call(A.cap, copytext(handler, 5))(A)
		else
			var/datum/run_on = A.holder
			. = call(run_on, handler)(A)
	catch(var/exception/fault)
		act_unwind(depth, chain_len, "hook_call [handler]", fault)
		throw fault
	GLOB.act_depth--

/// A gate (a when() part or adjusts when =) of hook H for the act: a var name, a proc of the holder x(datum/act/A) that answers TRUE, a
/// condition id or a condition tree. The context is the action's own typed act, so the gate reads its fields.
/proc/hook_gate(datum/hook/H, datum/act/A, cond)
	if(istext(cond) && !(cond in A.holder.vars))
		var/datum/run_on = A.holder
		return !!hook_call_plain(run_on, cond, A)
	return condition_holds(A.holder, cond)

/proc/hook_call_plain(datum/run_on, handler, datum/act/A)
	var/depth = GLOB.act_depth
	var/chain_len = length(GLOB.act_chain)
	GLOB.act_depth++
	try
		. = op_pure_call(run_on, handler, A)
	catch(var/exception/fault)
		act_unwind(depth, chain_len, "hook_call_plain [handler]", fault)
		throw fault
	GLOB.act_depth--

/// Runs the parts of a hook that gate and act, in order. Returns TRUE when every gate held (the hook took over). `A` is the context.
/proc/hook_run_parts(datum/hook/H, datum/act/A, list/parts)
	for(var/datum/entry/part as anything in parts)
		switch(part.kind)
			if(ENTRY_WHEN)
				if(!hook_gate(H, A, part.args["cond"]))
					return FALSE
				// when(cond, req_x(...)): requirements written beside the condition gate the hook too, asked in the action's context (an op's
				// origin, its actor): extend(/datum/act/op, instead(when(STAT_X, req_on_origin(ORIGIN_CLICK)), ...)).
				for(var/datum/entry/part/req/R in part.children)
					if(!istype(A, /datum/act/op) || !op_req_holds(A, R))
						return FALSE
			if(ENTRY_CHANCE)
				if(!TEST_ROLL(part.args["percent"]))
					return FALSE
			if(ENTRY_COALESCE)
				// coalesce(interval): the parts after it run once per window, from a timer (coalesce.dm); this trigger only opens or joins the window.
				coalesce_trigger(H, A, part)
				return FALSE
			if(ENTRY_GO)
				// go(/datum/capability/x): sets the mode of the holder (modes.dm). A go() that ends the state running this very entry ends the entry.
				modes_go(A, part)
				if(A.activation?.dead)
					return TRUE
			if(ENTRY_THEN)
				var/reply = hook_call(H, part.args["handler"], A)
				if(reply == HOOK_DECLINE)
					return FALSE
				if(!isnull(reply) && istype(A, /datum/act/action))
					var/datum/act/action/taken = A
					taken.reply = reply
			else
				act_run_part(A, H, part)
	return TRUE

/// A part kind E2 owns (sets, toggles, holds, releases, grants, fixes, says, plays, ...) inside an instead or an on_notice: the op engine's effect
/// and feedback parts, run on the action's context (the fields they read, holder, target, actor and held, are on every act).
/proc/act_run_part(datum/act/A, datum/hook/H, datum/entry/part)
	if(istype(part, /datum/entry/part/effect))
		var/datum/entry/part/effect/F = part
		hook_effect_report(A, F)
		return
	if(istype(part, /datum/entry/part/says))
		var/datum/entry/part/says/S = part
		S.feedback(A)
		return
	if(istype(part, /datum/entry/part/plays))
		var/datum/entry/part/plays/P = part
		P.feedback(A)
		return
	declare_report("hook on [A.holder?.type]: part [part.kind] cannot run in a hook (an effect, says() or plays() can)")

/// A needs hook's verdict: null to let the action go on, else the refusal reason. The hook's children are requirements (the part engine's
/// req_* constructors, or a legacy requirement with a form in the new engine), asked in the action's own context.
/proc/act_needs_refusal(datum/act/A, datum/hook/H)
	for(var/child in H.entry.children)
		if(istype(child, /datum/entry/part/req) || istype(child, /datum/requirement))
			if(!op_req_holds(A, child))
				return op_req_refusal(A, child)
	return null

// ---- the entry engines ----

/// An activation's extend() entries: act hooks onto the holder; other targets (an op key, a capability) are the op engine's.
/datum/entry_engine/hook_extend
	kind = ENTRY_EXTEND

/datum/entry_engine/hook_extend/apply(datum/activation/A, datum/entry/E, datum/centry/C)
	return hooks_attach(A, E, C)

/datum/entry_engine/hook_extend/remove(datum/activation/A, datum/entry/E)
	hooks_detach(A, E)

/datum/entry_engine/hook_notice
	kind = ENTRY_ON_NOTICE

/datum/entry_engine/hook_notice/apply(datum/activation/A, datum/entry/E, datum/centry/C)
	return hooks_attach(A, E, C)

/datum/entry_engine/hook_notice/remove(datum/activation/A, datum/entry/E)
	hooks_detach(A, E)

/// Registers the hooks of `E` on the activation's holder. TRUE when it made any.
/proc/hooks_attach(datum/activation/A, datum/entry/E, datum/centry/C)
	var/list/made = hooks_from_entry(E, C, A)
	if(!length(made))
		return FALSE
	var/datum/rx_state/rx = rx_of(A.holder)
	for(var/datum/hook/H as anything in made)
		LAZYADD(rx.hooks, H) // ALLOW(ownership): an engine record the one teardown path drops
	return TRUE

/proc/hooks_detach(datum/activation/A, datum/entry/E)
	var/datum/holder = A.holder
	if(!holder?.rx?.hooks)
		return
	for(var/datum/hook/H as anything in holder.rx.hooks.Copy())
		if(H.activation == A && H.source_entry == E)
			holder.rx.hooks -= H
			coalesce_cancel(holder, H)
			H.activation = null // ALLOW(ownership): an engine record the one teardown path drops
	if(!length(holder.rx.hooks))
		holder.rx.hooks = null

/datum/rx_state
	/// The /datum/hook records the live activations of this datum brought (the type's own are in its compiled table).
	var/list/hooks

/// Ends every reaction observation the listener made (observe(source, on_change(...), listener, handler), a notice reaction), on anything.
/// The count ended. unobserve_all() ends the hook activations of the other form.
/proc/unobserve_reactions(datum/listener)
	. = 0
	for(var/datum/rx_listener/L as anything in listener?.rx?.listening?.Copy())
		rx_listener_remove(L)
		.++
