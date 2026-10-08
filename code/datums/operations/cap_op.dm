// Operations as capabilities (doc/rewrite/dx_conventions.md, "Operations").
//
//	. += cap_op("Pry cover", PROC_REF(pry_cover), using = TOOL_CROWBAR, by = AFF_MANIPULATE, delay = 2 SECONDS,
//		needs = req_clear(CAP_LOCKED), action = ACT_PRY, kind = OP_STRUCTURAL, at = BAY_INTERIOR)
//	. += cap_require(OP_STRUCTURAL, needs = req_access())
//	. += refine("pry_cover", delay = 4 SECONDS)
//
// cap_op() is the one builder of a capability entry. cap_hand / cap_tool / cap_use_on / cap_insert are
// presets of it (they keep the old gating arguments and defaults: legacy = TRUE, no provider, no
// actor-state stage); cap_control() is the new preset for controls (a hand that can work an
// interface, over the physical or interface route). The old gating arguments (behind, blocked_by,
// locked_by, needs procs, works_*) still work: the target-contract stage runs them, and they are
// also mapped onto requirements (op.gating) so a waiting operation cancels early when one of their
// bits changes.
//
// A non-legacy op has a key ("op:<key>"): declaring a key twice on one type is an init error unless
// the second is a refine() of the first or says replace = TRUE.

/// The definition behind one cap_op(): who can do it, with what, how, and what it needs.
/datum/op_def
	/// Unique per type (non-legacy): refine() and cap_require(ops =) name it.
	var/key
	var/name
	/// OP_CONTROL / OP_STRUCTURAL / OP_EMERGENCY.
	var/kind = OP_CONTROL
	/// ACT_*: which action this op answers: the gesture vocabulary (a gesture reaches actions through the actor's bind
	/// profile). ACT_NONE: no gesture reaches it; it is chosen by its key or name (Menu, radial, command bar).
	var/action = ACT_USE
	/// Higher first among the ops answering one action (gesture resolution: the profile's action list, then this, then
	/// declaration order). OP_PRIORITY_*.
	var/priority = 0
	/// The stances (I_* values) the op answers, or null for any: a list form of cap_op(stance =) (an offered requirement,
	/// req_stance()); a single stance sits on the entry, as the resolver's selector.
	var/list/stances
	/// What it is used with: null (bare hand), a TOOL_* quality, an item type (or list), or a /datum/req.
	var/using
	/// AFF_* bits the actor's provider slot must give (NONE for none).
	var/by = NONE
	/// ROUTE_* bits this op accepts.
	var/via = ROUTE_PHYSICAL
	/// BAY_*: the compartment of the target this op works through, or null.
	var/at
	/// Deciseconds it takes.
	var/delay = 0
	/// Tool resource (fuel, charge) it uses.
	var/cost = 0
	/// A /datum/msg shown when a timed op starts.
	var/start_msg
	/// PROC_REF on the holder.
	var/handler
	/// The op's own requirements (a list of /datum/req), the last stage.
	var/list/needs
	/// What makes the op meant at all (`offered =`, an empty hand): while one fails the input falls through to the next
	/// interaction, as if the op were not there. Unlike `needs`, a failure is no refusal.
	var/list/offered
	/// The old gating arguments as requirements (behind, blocked_by, locked_by): reads for early cancel.
	var/list/gating
	/// Item types (a list) that a plain click (GESTURE_CLICK) must hold to reach this op: a card swiped across a lock.
	/// Other gestures reach it with whatever is in hand. Null: no such rule.
	var/list/click_with
	/// Made by a preset: skips the actor-state stage and takes no provider unless asked.
	var/legacy = FALSE
	/// Declared with replace = TRUE: may replace an earlier op with the same key.
	var/replaces = FALSE
	/// The arguments it was built from (refine() rebuilds from them). A cache, not a setting.
	var/tmp/list/spec

/// The shape names cap_op() builds an entry for.
#define OP_SHAPE_HAND "hand"
#define OP_SHAPE_TOOL "tool"
#define OP_SHAPE_USE_ON "use_on"
#define OP_SHAPE_INSERT "insert"

/**
 * One operation. name/handler as for cap_hand(); handler is a proc on the holder, (mob/user, ...)
 * (held-item shapes also get `held`).
 *	using	null (empty hand), a TOOL_* quality, an item type or list of types, or a /datum/req.
 *	by		AFF_* bits the actor's provider slot must give. Default AFF_MANIPULATE (AFF_CONTROL for controls).
 *	via		ROUTE_* bits accepted. Default ROUTE_PHYSICAL (controls also ROUTE_INTERFACE).
 *	action	the ACT_* it answers (default ACT_USE): the gesture vocabulary. ACT_NONE: no gesture reaches it (the Menu,
 *			radial and command bar do, by its key or name: the old INTERACT_VERB). ACT_ATTACK: the hostile use, reached by a
 *			click in a hostile stance before ACT_USE.
 *	priority	higher first among the ops of one action (OP_PRIORITY_*): the profile's action list, then this, then
 *			declaration order decide what a gesture reaches.
 *	stance	I_HELP / I_DISARM / I_GRAB / I_HURT, or a list of them: the op is meant only in those stances (an offered
 *			requirement: another stance falls through to the next op).
 *	needs	a /datum/req or list of them (the op's own needs); old-style proc refs are passed to the
 *			target contract as before.
 *	offered	a /datum/req or list: while one fails the op is not meant (the input falls through); not a refusal.
 *			`using = EMPTY_HAND` is offered too. Kind OP_STRUCTURAL works broken and unpowered unless it says not.
 *	delay	deciseconds; the wait re-checks everything when it ends and cancels early when a requirement's read changes.
 *	cost	tool resource used (welder fuel).
 *	start_msg	a /datum/msg type shown when a timed op starts.
 *	kind	OP_CONTROL, OP_STRUCTURAL or OP_EMERGENCY.
 *	key		the op's key (default: the snake_case name).
 *	at		BAY_*: the compartment it works through.
 *	log		LOG_GAME / LOG_ADMIN.
 *	replace	TRUE to replace an earlier op of the same key instead of raising the init error.
 *	click_with	item types a plain click must hold to reach the op (a swipe); passes_held: the handler also gets `held`.
 *	entry	INTERACTION_ENTRY_*: the legacy entry proc (attack_hand, attackby, attack_self, click_alt) that also runs the op,
 *			for callers that still call it directly (a silicon's hand use through silicon_use, a computer's item fallback)
 *			until they migrate. The click router runs the op first either way.
 * The remaining arguments are the old gating arguments of cap_hand()/cap_tool()/...
 */
/proc/cap_op(name, handler, using, by, via, action, needs, delay, cost, start_msg, kind = OP_CONTROL, key, at, log, replace = FALSE, shape, legacy = FALSE, behind = NONE, blocked_by = NONE, locked_by = NONE, else_say, works_broken, works_unpowered, list/form, priority, stance, name_proc, applies, cooldown, volume, list/click_with, passes_held, offered, entry)
	var/list/spec = list(
		"name" = name, "handler" = handler, "using" = using, "by" = by, "via" = via, "action" = action,
		"needs" = needs, "delay" = delay, "cost" = cost, "start_msg" = start_msg, "kind" = kind, "key" = key,
		"at" = at, "log" = log, "replace" = replace, "shape" = shape, "legacy" = legacy, "behind" = behind,
		"blocked_by" = blocked_by, "locked_by" = locked_by, "else_say" = else_say,
		"works_broken" = works_broken, "works_unpowered" = works_unpowered, "form" = form,
		"priority" = priority, "stance" = stance, "name_proc" = name_proc, "applies" = applies,
		"cooldown" = cooldown, "volume" = volume, "click_with" = click_with, "passes_held" = passes_held, "offered" = offered,
		"entry" = entry,
	)
	return cap_op_build(spec)

/// The shape of an op from what it is used with.
/proc/op_shape_of(using)
	if(isnull(using) || istype(using, /datum/req))
		return OP_SHAPE_HAND
	if(istext(using))
		return OP_SHAPE_TOOL
	return OP_SHAPE_USE_ON

/// Builds the capability for an op spec (cap_op()'s named arguments as an assoc list).
/proc/cap_op_build(list/spec)
	var/shape = spec["shape"] || op_shape_of(spec["using"])
	var/legacy = spec["legacy"]
	var/using = spec["using"]
	// Old-style needs (procs) go to the target contract; requirements to the op.
	var/list/reqs = list()
	var/list/procs
	var/needs = spec["needs"]
	for(var/entry in (islist(needs) ? needs : list(needs)))
		if(isnull(entry))
			continue
		if(istype(entry, /datum/req))
			reqs += entry
		else if(islist(entry))
			reqs += req_list(entry)
		else
			LAZYADD(procs, entry)
	// Shape defaults (the old constructors' own).
	var/works_broken = spec["works_broken"]
	var/works_unpowered = spec["works_unpowered"]
	var/structural = spec["kind"] == OP_STRUCTURAL
	if(isnull(works_broken))
		works_broken = structural || shape == OP_SHAPE_TOOL
	if(isnull(works_unpowered))
		works_unpowered = structural || shape == OP_SHAPE_TOOL || shape == OP_SHAPE_INSERT
	var/held_type
	var/quality
	if(shape == OP_SHAPE_TOOL)
		quality = using
	else if(shape == OP_SHAPE_USE_ON || shape == OP_SHAPE_INSERT)
		held_type = using
	var/entry_kind = shape
	// One stance sits on the entry (the resolver's selector, and the stance its effect reads); several are an offered
	// requirement of the op.
	var/stance = spec["stance"]
	var/list/stances = islist(stance) ? stance : null
	var/datum/capability/entry/C = cap_entry(entry_kind, spec["name"], spec["handler"], spec["behind"], spec["locked_by"], procs, spec["else_say"], works_broken, works_unpowered, spec["log"], spec["form"], held_type, quality, spec["delay"], spec["priority"], stances ? null : stance, spec["name_proc"], spec["applies"], spec["blocked_by"], spec["cooldown"], spec["cost"] || 0, spec["volume"])
	var/datum/interaction/capability/E = C.entry
	var/datum/op_def/op = new
	op.name = spec["name"]
	op.key = spec["key"] || replacetext(lowertext("[spec["name"]]"), " ", "_")
	op.kind = spec["kind"] || OP_CONTROL
	op.action = spec["action"] || ACT_USE
	op.priority = spec["priority"] || 0
	op.stances = stances
	// No gesture reaches an ACT_NONE op: the resolver answers no input with it either (the Menu lists it).
	if(op.action == ACT_NONE)
		E.default_action = null
	if(spec["entry"])
		E.entry = spec["entry"]
	op.using = istype(using, /datum/req) ? using : (shape == OP_SHAPE_HAND ? null : using)
	op.legacy = legacy
	var/by = spec["by"]
	if(isnull(by))
		by = legacy ? NONE : AFF_MANIPULATE
	op.by = by
	var/via = spec["via"]
	op.via = isnull(via) ? ROUTE_PHYSICAL : via
	op.at = spec["at"]
	op.delay = spec["delay"] || 0
	op.cost = spec["cost"] || 0
	op.start_msg = spec["start_msg"]
	op.handler = spec["handler"]
	op.click_with = spec["click_with"]
	if(spec["passes_held"])
		E.passes_held = TRUE
	op.needs = reqs
	op.offered = req_list(spec["offered"])
	if(stances)
		op.offered += req_stance(stances)
	op.gating = req_from_gating(spec["behind"], spec["blocked_by"], spec["locked_by"])
	op.replaces = spec["replace"]
	op.spec = spec
	if(istype(using, /datum/req))
		// A requirement as the thing used: the op needs it of the held item (checked in the needs stage).
		op.needs = list(using) + reqs
		if(istype(using, /datum/req/empty_hand))
			op.offered = list(using) + op.offered
	if(op.start_msg)
		E.start_feedback = op.start_msg
	// Flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	E.op = op
	if(!legacy)
		C.key = "op:[op.key]"
	return C

/// The op behind a capability, or null when it isn't a cap_op() one.
/proc/cap_op_of(datum/capability/C)
	RETURN_TYPE(/datum/op_def)
	var/datum/capability/entry/E = C
	if(!istype(E))
		return null
	return E.entry?.op

// ---- the presets ----

/// An empty-hand action: cap_hand("Toggle", PROC_REF(toggle)). Handler (mob/user).
/proc/cap_hand(name, handler, behind = NONE, locked_by = NONE, needs, else_say, works_broken = FALSE, works_unpowered = FALSE, log, list/form, priority, stance, name_proc, applies, blocked_by = NONE, delay, cooldown)
	return cap_op(name, handler, by = NONE, needs = needs, delay = delay, log = log, shape = OP_SHAPE_HAND, legacy = TRUE, behind = behind, blocked_by = blocked_by, locked_by = locked_by, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, form = form, priority = priority, stance = stance, name_proc = name_proc, applies = applies, cooldown = cooldown)

/// A tool action: cap_tool("Unbolt", TOOL_WRENCH, PROC_REF(unbolt), delay = 2 SECONDS). Handler (mob/user, obj/item/held).
/// `fuel`: welder fuel (or other tool resource) used; `volume`: the tool sound's volume (0 for none).
/proc/cap_tool(name, quality, handler, delay, behind = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, list/form, priority, name_proc, applies, blocked_by = NONE, fuel = 0, volume, cooldown)
	return cap_op(name, handler, using = quality, by = NONE, needs = needs, delay = delay, cost = fuel, log = log, shape = OP_SHAPE_TOOL, legacy = TRUE, behind = behind, blocked_by = blocked_by, locked_by = locked_by, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, form = form, priority = priority, name_proc = name_proc, applies = applies, cooldown = cooldown, volume = volume)

/// Using a held item of `held_type` on the holder, which keeps the item. Handler (mob/user, obj/item/held).
/proc/cap_use_on(name, held_type, handler, behind = NONE, locked_by = NONE, needs, else_say, works_broken = FALSE, works_unpowered = FALSE, log, list/form, priority, stance, name_proc, applies, blocked_by = NONE, delay, cooldown)
	return cap_op(name, handler, using = held_type, by = NONE, needs = needs, delay = delay, log = log, shape = OP_SHAPE_USE_ON, legacy = TRUE, behind = behind, blocked_by = blocked_by, locked_by = locked_by, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, form = form, priority = priority, stance = stance, name_proc = name_proc, applies = applies, cooldown = cooldown)

/// Putting a held item of `held_type` into the holder (the handler adopts it: rel_set moves it).
/proc/cap_insert(name, held_type, handler, behind = NONE, locked_by = NONE, needs, else_say, works_broken = FALSE, works_unpowered = TRUE, log, list/form, priority, name_proc, applies, blocked_by = NONE, delay, cooldown)
	return cap_op(name, handler, using = held_type, by = NONE, needs = needs, delay = delay, log = log, shape = OP_SHAPE_INSERT, legacy = TRUE, behind = behind, blocked_by = blocked_by, locked_by = locked_by, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, form = form, priority = priority, name_proc = name_proc, applies = applies, cooldown = cooldown)

/// A control: an empty hand (or any provider with AFF_CONTROL) working the holder's interface, over
/// the physical or the interface route. Handler (mob/user). Strict: needs a capable actor.
/proc/cap_control(name, handler, needs, action = ACT_USE, delay, kind = OP_CONTROL, key, at, log, behind = NONE, blocked_by = NONE, locked_by = NONE, else_say, works_broken, works_unpowered, list/form, priority, name_proc, applies, cooldown, using, offered, stance, entry)
	return cap_op(name, handler, using = using, offered = offered, by = AFF_CONTROL, via = ROUTE_PHYSICAL | ROUTE_INTERFACE, action = action, needs = needs, delay = delay, kind = kind, key = key, at = at, log = log, shape = OP_SHAPE_HAND, behind = behind, blocked_by = blocked_by, locked_by = locked_by, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, form = form, priority = priority, stance = stance, name_proc = name_proc, applies = applies, cooldown = cooldown, entry = entry)

// ---- cap_require ----

/// An additive contract on the operations of its holder: every op it covers (by key or by kind,
/// or all ops when `ops` is null) also needs these requirements, checked in the capability stage.
/datum/capability/require
	/// Op keys and OP_* kinds it covers; null covers every op.
	var/list/ops
	var/list/reqs

/datum/capability/require/proc/covers(datum/op_def/op)
	if(!length(ops))
		return TRUE
	return (op.key in ops) || (op.kind in ops)

/// ops: an op key, an OP_* kind, a list of either, or null (every op). needs: a requirement or list.
/proc/cap_require(ops, needs)
	var/datum/capability/require/C = new
	if(!isnull(ops))
		C.ops = islist(ops) ? ops : list(ops)
	C.reqs = req_list(needs)
	C.key = "require:[md5(datum_signature(list(C.ops, C.reqs)))]"
	return C

// ---- refine ----

/// A change to an op declared earlier on the type (or by a bundle): the refined op replaces it in
/// place. caps_intern_list() applies it; refining a key nothing declared is an init error. A key that
/// names a capability which is not an op refines that capability: its refined() makes the replacement
/// from the same named fields.
/// key: the op's key (or a capability's). delay: the new wait. effect: the new handler (PROC_REF). input: the new
/// `using`. action: the new ACT_*. priority: the new OP_PRIORITY_*. No field has two meanings. (A reagent holder is
/// reagents() in a CAPABILITIES block, changed with configure(reagents(...)): code/library/reagents/reagents.dm.)
/proc/refine(key, delay, effect, input, action, priority)
	var/datum/capability/refine/C = new
	C.base_key = key
	var/list/o = list()
	if(!isnull(delay))
		o["delay"] = delay
	if(!isnull(effect))
		o["handler"] = effect
	if(!isnull(input))
		o["using"] = input
	if(!isnull(action))
		o["action"] = action
	if(!isnull(priority))
		o["priority"] = priority
	C.overrides = o
	C.key = "refine:[key]:[md5(datum_signature(o))]"
	return C

/// The op capability `base` with refinement `R` applied (a fresh capability built from its spec).
/proc/cap_op_refined(datum/capability/base, datum/capability/refine/R)
	var/datum/op_def/op = cap_op_of(base)
	var/list/spec = op.spec.Copy()
	for(var/name in R.overrides)
		spec[name] = R.overrides[name]
	return cap_op_build(spec)

// ---- the entry ----

/datum/interaction/capability
	/// The operation this entry runs, when it was built by cap_op() (null for library entries).
	var/datum/op_def/op

/// The route the current call reaches the target by; perform_action() sets it around a call.
GLOBAL_VAR_INIT(op_route_now, ROUTE_PHYSICAL)
/// The GESTURE_* an action lookup is resolving for (resolve_gesture() sets it), or null when the lookup is not a
/// gesture's (a radial pick, the UI, a verb). An op's `click_with` rule reads it.
GLOBAL_VAR(op_gesture_now)

/// Whether a phrase from a reason type reads inside "Name: <reason>.".
/proc/req_reason_phrase(reason_type, datum/op_ctx/ctx)
	var/text = req_reason_text(reason_type, ctx)
	if(!text)
		return text
	if(copytext(text, length(text)) == ".")
		text = copytext(text, 1, length(text))
	if(reason_type != /datum/msg/req_refused && length(text) > 1)
		text = lowertext(copytext(text, 1, 2)) + copytext(text, 2)
	return text

/// An op entry's refusal: the resolver predicate (physical route only: reach, selectors), then the
/// ordered stages of an op_ctx. Null when it may run.
/proc/op_entry_reason(datum/interaction/capability/E, mob/actor, atom/target, obj/item/held, why_predicate)
	if(why_predicate)
		return why_predicate
	var/datum/op_ctx/ctx = op_ctx_take(actor, target, held, E.op, GLOB.op_route_now)
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	ctx.entry = E
	var/why = ctx.check()
	. = why ? req_reason_phrase(why, ctx) : null
	ctx.release()

/// Whether this op entry waits through the op wait (a pending context that cancels early on its requirements' reads);
/// FALSE for an entry that pays its time through the tool pipeline (a construction step, whose start lines it prints).
/datum/interaction/capability/proc/op_waits()
	return TRUE

/datum/interaction/capability/pay_cost(mob/actor, atom/target, obj/item/held)
	if(!op || tool || duration <= 0 || !op_waits())
		return ..()
	if(after_pending(actor, "op_wait"))
		to_chat(actor, span_warning("You are already busy."))
		return FALSE
	var/datum/op_ctx/ctx = op_ctx_take(actor, target, held, op, GLOB.op_route_now)
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	ctx.entry = src
	ctx.check(OP_STAGE_PROVIDER)
	op_pending_add(ctx)
	var/msg_type = start_feedback_for(actor, target, held)
	if(msg_type)
		act_message_t(actor, target, msg_type, held)
	if(!after_slot(actor, "op_wait", duration_for(actor, target, held), GLOBAL_PROC_REF(op_wait_done), ctx.id))
		ctx.release()
		return FALSE
	return USE_TOOL_PENDING

/// Whether declaring capability `later` where `earlier` already sits is the init error: two non-legacy
/// ops of one key, the later without replace = TRUE. (refine() never gets here: it edits in place.)
/proc/cap_op_key_conflict(datum/capability/later, datum/capability/earlier)
	var/datum/op_def/newer = cap_op_of(later)
	var/datum/op_def/older = cap_op_of(earlier)
	return newer && older && !newer.legacy && !older.legacy && !newer.replaces

/datum/capability/entry/operation_conflicts(datum/capability/earlier)
	return cap_op_key_conflict(src, earlier)

/datum/capability/entry/operation_key()
	return cap_op_of(src)?.key

/datum/capability/entry/operation_refined(datum/capability/refine/R)
	return cap_op_refined(src, R)
