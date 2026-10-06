// Parts (doc/rewrite/final_api.html, section 9 "Ops and parts"; section 19 "E2, parts").
//
// An op is a list of parts. Every behaviour of an op is a part: a binding that says which input reaches it, a condition that says when it
// exists, a requirement that says what it needs, a wait, a cost, an effect, a message. A part is a flyweight /datum/entry subtype
// (entries.dm interns it by signature, so `hand()` is one datum wherever it is written and a type that adds nothing shares its parent's
// compiled table), its parameters are its `args`, and the stage hooks it implements are procs on its type:
//
//   match(A)       Match: TRUE when the op is what the actor is doing (silent on failure)
//   require(A)     Require: TRUE when allowed; reason(A) gives the /datum/msg type shown when not
//   wait_time(A)   Wait: how long
//   run_effect(A)  Do: the work, returning an OP_* report (the design's do(A); `do` is a DM keyword)
//
// The op compiler (plan.dm) reads the parts of an op and its extends, merges them by their combine rules into one /datum/op_plan, and the
// engine (run.dm) walks the plan stage by stage. Parts never hold per-act state: that lives on the act and the pending op.

/// Base of every part. Never instantiated.
/datum/entry/part
	kind = ENTRY_OP_PART
	/// The stages this part acts in (PART_STAGE_* bits): documentation for explain output and the build checks.
	var/stages = PART_STAGE_NONE
	/// The name explain output prints ("hand", "wait", "costs").
	var/part_name = "part"

/// The one text an explain dump prints for the part: "hand", "wait(30)", "costs(2, 1)".
/datum/entry/part/proc/describe()
	var/list/bits = list()
	for(var/name in src.args)
		var/value = src.args[name]
		if(isnull(value) || value == FALSE)
			continue
		bits += islist(value) ? jointext(value, ", ") : "[value]"
	return length(bits) ? "[part_name]([jointext(bits, ", ")])" : part_name

/// Match: does the op match this input? Silent.
/datum/entry/part/proc/match(datum/act/op/A)
	return TRUE

/// Require: is it allowed now?
/datum/entry/part/proc/require(datum/act/op/A)
	return TRUE

/// The /datum/msg type shown when require() said no.
/datum/entry/part/proc/reason(datum/act/op/A)
	return /datum/msg/req_failed

/// Wait: how long, in deciseconds (0: no timed wait).
/datum/entry/part/proc/wait_time(datum/act/op/A)
	return 0

/// Do: the work. Returns OP_OK, OP_REFUSED, OP_REPLACED or OP_FAILED (nothing returned is OP_OK).
/datum/entry/part/proc/run_effect(datum/act/op/A)
	return OP_OK

/// Folds this part into the plan being compiled. `level` is the precedence level it was declared at (library default, the op's own parts,
/// a group extend, a key extend). The default is to do nothing: a part with no compile work only acts through its stage hooks.
/datum/entry/part/proc/compile(datum/op_plan/P, level)
	return

/// Builds (and interns) one part of `part_type` with the named `args` and the child entries it nests.
/proc/part_make(part_type, list/args, list/children)
	RETURN_TYPE(/datum/entry/part)
	var/static/list/interned = list()
	var/sig = "[part_type]|" + entry_signature(ENTRY_OP_PART, null, args, children)
	var/datum/entry/part/known = interned[sig]
	if(known)
		return known
	var/datum/entry/part/P = new part_type
	P.args = args && length(args) ? args : null
	P.children = children && length(children) ? children : null
	P.sig = sig
	interned[sig] = P
	return P

/// A part's named argument, or null.
/datum/entry/part/proc/arg_value(name)
	return src.args ? src.args[name] : null

// ---- the op itself and the extend parts ----

/// The slots an op or an extend takes parts in. More than this many go in one list (a bundle).
#define OP_PART_SLOTS p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15, p16
#define OP_PART_LIST list(p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15, p16)

/// op(key, binding | inputs(bindings...), parts...): an op. The key is a literal: a capability's ops are namespaced by it automatically.
/proc/op(key, OP_PART_SLOTS)
	if(!istext(key) || !length(key))
		declare_report("op(): the first argument is the op's key (a literal text), got [isnull(key) ? "null" : "[key]"]")
		return null
	return entry_make(ENTRY_OP, key, null, entry_flatten(OP_PART_LIST))

// ---- bindings ----

/// An input binding: which input reaches the op, with what origin, reach, provider affordance, authority, intent and tier (section 8).
/datum/entry/part/bind
	part_name = "binding"
	stages = PART_STAGE_MATCH
	/// BIND_*.
	var/bind_kind = BIND_HAND

/datum/entry/part/bind/hand
	part_name = "hand"
	bind_kind = BIND_HAND

/datum/entry/part/bind/tool
	part_name = "tool"
	bind_kind = BIND_TOOL

/datum/entry/part/bind/item
	part_name = "item"
	bind_kind = BIND_ITEM

/datum/entry/part/bind/stack
	part_name = "stack"
	bind_kind = BIND_STACK

/datum/entry/part/bind/in_hand
	part_name = "in_hand"
	bind_kind = BIND_IN_HAND

/datum/entry/part/bind/at_target
	part_name = "at_target"
	bind_kind = BIND_AT_TARGET

/datum/entry/part/bind/inside
	part_name = "inside"
	bind_kind = BIND_INSIDE

/datum/entry/part/bind/remote
	part_name = "remote"
	bind_kind = BIND_REMOTE

/datum/entry/part/bind/menu
	part_name = "menu"
	bind_kind = BIND_MENU

/datum/entry/part/bind/ui_act
	part_name = "ui_act"
	bind_kind = BIND_UI

/datum/entry/part/bind/topic
	part_name = "topic"
	bind_kind = BIND_TOPIC

/datum/entry/part/bind/ai
	part_name = "ai"
	bind_kind = BIND_AI

/datum/entry/part/bind/clicks
	part_name = "clicks"
	bind_kind = BIND_CLICKS

/datum/entry/part/bind/tk
	part_name = "tk"
	bind_kind = BIND_TK

/datum/entry/part/bind/observe
	part_name = "observe"
	bind_kind = BIND_OBSERVE

/// hand(): the actor's hand on the target.
/proc/hand()
	return part_make(/datum/entry/part/bind/hand)

/// tool(Q): a held tool of quality Q on the target.
/proc/tool(quality)
	return part_make(/datum/entry/part/bind/tool, list("quality" = list(quality)))

/// any_of_tools(Q...): a held tool of any of these qualities.
/proc/any_of_tools(...)
	return part_make(/datum/entry/part/bind/tool, list("quality" = entry_flatten(args)))

/// item(T): the held item is a T.
/proc/item(item_type)
	return part_make(/datum/entry/part/bind/item, list("type" = item_type))

/// stack(T, n): the held item is a stack of T, and n of its units are the op's cost.
/proc/stack(item_type, n = 1)
	return part_make(/datum/entry/part/bind/stack, list("type" = item_type, "n" = n))

/// in_hand(): the held item used on itself.
/proc/in_hand()
	return part_make(/datum/entry/part/bind/in_hand)

/// at_target(filter): the held item's op, done to a target of type `filter` (any target when null).
/proc/at_target(filter = null)
	return part_make(/datum/entry/part/bind/at_target, list("filter" = filter))

/// inside(): acting on the container the actor is inside.
/proc/inside()
	return part_make(/datum/entry/part/bind/inside)

/// remote(): through an interface at a distance (a silicon's remote use, a console).
/proc/remote()
	return part_make(/datum/entry/part/bind/remote)

/// menu(button =, bind =): chosen by key: an ability's button and keybind, or a target's menu entry.
/proc/menu(button = null, bind = null)
	return part_make(/datum/entry/part/bind/menu, list("button" = button, "bind" = bind))

/// ai(): an AI controller or a script calls the op by key.
/proc/ai()
	return part_make(/datum/entry/part/bind/ai)

/// clicks(): the actor's own op, performed on whatever the actor clicks (a player-controlled mob's natural weapon: the bite of a carp). The op belongs to the
/// actor and not to the clicked thing, so it is a candidate only on the actor's side; it is physical, so the actor has to be able to act. Beside ai(), it is
/// the input a player uses for the op an AI behaviour reaches by key.
/proc/clicks()
	return part_make(/datum/entry/part/bind/clicks)

/// tk(): the hand's touch of a target the actor reaches only with its mind: out of every hand's reach, in sight, within TK_RANGE (the old INTERACT_TK; an
/// attack_tk() override). The telekinesis provider (AFF_TELEKINESIS, tk_ready(): a TK mutation, or powered kinesis gloves) does it, so the actor half of the hand gate
/// holds (a conscious actor who is not stunned) and the machine half never does: a mind has no posture or dexterity, and a machine's power is the op's own business.
/// The op sits one tier above hand ops, because a TK actor's other providers also reach what it sees (design: any hand op at range): at range the op
/// that means telekinesis goes first, and next to the actor the hand's op does.
/proc/tk()
	return part_make(/datum/entry/part/bind/tk)

/// observer(): a ghost's click or menu pick on the target (the old INTERACT_OBSERVER, attack_ghost). The binding needs AFF_OBSERVE, which only the observer
/// mob provides (CAPABILITIES(/mob/observer/dead)), so no living actor ever reaches the op and a ghost reaches no hand, tool or remote op. Reach is REACH_ANY
/// (a ghost is anywhere it looks), it is not physical (no req_capable(): a ghost is dead by definition), and a target's requirements still apply.
/proc/observer()
	return part_make(/datum/entry/part/bind/observe)

/// ui_act(args...) or ui_act("name", args...): a window button. The window action is the op's key unless a name is given. The arguments
/// are arg(name, schema) parts.
/proc/ui_act(name = null, ...)
	var/list/rest = args.Copy()
	var/action = null
	if(istext(name))
		action = name
		rest.Cut(1, 2)
	return part_make(/datum/entry/part/bind/ui_act, list("action" = action), entry_flatten(rest))

/// topic("key", args...): a Topic link.
/proc/topic(key, ...)
	var/list/rest = args.Copy(2)
	return part_make(/datum/entry/part/bind/topic, list("key" = key), entry_flatten(rest))

/// inputs(bindings...): the whole set of an op's bindings; in an extend it replaces them.
/proc/inputs(...)
	return part_make(/datum/entry/part/inputs, null, entry_flatten(args))

/// binds(binding...): one more binding for an inherited op.
/proc/binds(...)
	return part_make(/datum/entry/part/binds, null, entry_flatten(args))

/// Groups bindings (op(key, inputs(hand(), ui_act()), ...)).
/datum/entry/part/inputs
	part_name = "inputs"
	stages = PART_STAGE_MATCH

/datum/entry/part/binds
	part_name = "binds"
	stages = PART_STAGE_MATCH

/// A UI or topic argument: arg(name, schema) validates a value the player sent, arg(name, from = nameof(v)) takes a tracked var's schema.
/datum/entry/part/ui_arg
	part_name = "arg"

/// optional = TRUE: a link or button may leave the value out, and the handler gets null (a present value still crosses the schema).
/// among = SOURCE: a ref arg names its thing by the text of its ref, and is looked up only in SOURCE (TOPIC_IN_MOBS, TOPIC_IN_WORLD, TOPIC_IN_CONTENTS, a
/// proc on the holder that returns the list to search, ...: topic_resolve_ref()) instead of anywhere locate() reaches.
/proc/arg(name, datum/schema/schema = null, from = null, optional = FALSE, among = null)
	return part_make(/datum/entry/part/ui_arg, list("name" = name, "schema" = schema, "from" = from, "optional" = optional, "among" = among))

// ---- select parts (each replaces one column of what the binding implies) ----

/datum/entry/part/select
	part_name = "select"
	stages = PART_STAGE_MATCH
	/// Which column: "origin", "reach", "by", "authority", "gesture", "stance", "answers", "presents", "ungated".
	var/column

/datum/entry/part/select/origin
	part_name = "origin"
	column = "origin"

/datum/entry/part/select/reach
	part_name = "reach"
	column = "reach"

/datum/entry/part/select/by
	part_name = "by"
	column = "by"

/datum/entry/part/select/authority
	part_name = "authority"
	column = "authority"

/datum/entry/part/select/gesture
	part_name = "gesture"
	column = "gesture"

/datum/entry/part/select/stance
	part_name = "stance"
	column = "stance"

/datum/entry/part/select/answers
	part_name = "answers"
	column = "answers"

/datum/entry/part/select/presents
	part_name = "presents"
	column = "presents"

/datum/entry/part/select/ungated
	part_name = "ungated"
	column = "ungated"

/// ungated(): the op's hand binding skips the machine half of the hand gate (power, posture, dexterity: what the old attack_hand did before `..()`;
/// INTERACT_HAND_UNGATED). Every hand() op is refused for an actor who is unconscious or stunned; without ungated() one on a machine is also refused for
/// a machine that does not work and an actor who is down or cannot use their hands.
/proc/ungated()
	return part_make(/datum/entry/part/select/ungated, list("value" = TRUE))

/// answers(INTENT_X...): the intents the op answers (replaces what the binding implies).
/proc/answers(...)
	return part_make(/datum/entry/part/select/answers, list("value" = entry_flatten(args)))

/// hostile(): sugar for answers(INTENT_ATTACK), and the op yields the attack tier.
/proc/hostile()
	return part_make(/datum/entry/part/select/answers, list("value" = list(INTENT_ATTACK), "hostile" = TRUE))

/// origin(mask): the origins that reach the op.
/proc/origin(mask)
	return part_make(/datum/entry/part/select/origin, list("value" = mask))

/// reach(policy): REACH_ADJACENT, REACH_RANGE(n), REACH_INSIDE, REACH_VIEW or REACH_ANY.
/proc/reach(policy)
	return part_make(/datum/entry/part/select/reach, list("value" = policy))

/// by(affordances): what the provider must give.
/proc/by(affordances)
	return part_make(/datum/entry/part/select/by, list("value" = affordances))

/// authority(mask): the authorities the op accepts.
/proc/authority(mask)
	return part_make(/datum/entry/part/select/authority, list("value" = mask))

/// gesture(G): pins a raw gesture. Rare.
/proc/gesture(gesture_id)
	return part_make(/datum/entry/part/select/gesture, list("value" = gesture_id))

/// stance(S...): sugar for when(req_stance(S...)).
/proc/stance(...)
	return part_make(/datum/entry/part/select/stance, list("value" = entry_flatten(args)))

/// presents(T): the held item is a credential of type T, not "used" (intent INTENT_PRESENT).
/proc/presents(item_type)
	return part_make(/datum/entry/part/select/presents, list("value" = item_type))

// ---- Match: when(cond...) is E1's when() entry; in an op it is the Match condition ----
// (E1's when(cond, entries...) with no child entries is the Match form: the op compiler reads an ENTRY_WHEN child of an op as a condition.)

// ---- Require: needs(req...) and the bay ----

/// needs(req...): the requirements an op has to meet to run. Accumulates.
/proc/needs(...)
	return part_make(/datum/entry/part/needs, null, entry_flatten(args))

/datum/entry/part/needs
	part_name = "needs"
	stages = PART_STAGE_REQUIRE

// ---- Wait: wait(t), asks(), confirms(), captures() ----

/// wait(t, keeps = WAIT_KEEPS_DEFAULT): a timed wait, scaled by the held tool's speed. `t` is a number of deciseconds, or a PROC_REF(x) that returns one.
/proc/wait(t, keeps = WAIT_KEEPS_DEFAULT)
	return part_make(/datum/entry/part/wait, list("t" = t, "keeps" = keeps))

/datum/entry/part/wait
	part_name = "wait"
	stages = PART_STAGE_WAIT

/// How long the wait lasts (the held tool's speed scales the profile's base: tool_quality(Q, speed = 1.5) makes it shorter).
/datum/entry/part/wait/wait_time(datum/act/op/A)
	var/t = src.args["t"]
	if(istext(t)) // wait(PROC_REF(x)) / wait(CAP_PROC(x)): x(datum/act/A) returns the time in deciseconds, read when the op starts (a repair that takes as long as the damage)
		t = op_call(A, t) || 0
	var/speed = op_var(A.held, "tool_speed")
	return (isnum(speed) && speed > 0 && A.binding?.bind_kind == BIND_TOOL) ? t / speed : t

/// asks(/datum/request/x, field = v..., step =, resume =, keeps =, when =): a workflow step. DM cannot carry free named arguments through one
/// proc, so the request's fields go in `fields` as a list(name = value) the call names (asks(/datum/prompt/text/rename, fields = list("a" = 1))).
/// `when` (a condition: a var, a stat, a tree, or a PROC_REF x(datum/act/op/A)) is read when the step is reached: the step is skipped, with no
/// prompt, while it does not hold (a PIN is asked only of a card that has one). A skipped step leaves A.answer as it was.
/proc/asks(request_type, list/fields = null, step = null, resume = CAPTURE, keeps = WAIT_KEEPS_DEFAULT, when = null)
	return part_make(/datum/entry/part/asks, list("type" = request_type, "fields" = fields, "step" = step, "resume" = resume, "keeps" = keeps, "when" = when))

/datum/entry/part/asks
	part_name = "asks"
	stages = PART_STAGE_WAIT

/// computed(PROC_REF(x)): a field value of an asks() read from the holder when the question is opened: x(datum/act/A) returns it (the question text
/// of a door that says what it would do now). A plain text field is a literal, and one naming a var of the holder reads that var.
/proc/computed(handler)
	return list("computed", handler)

/// confirms("text"): asks(/datum/prompt/yes_no, question = "text"); a "no" ends the op and nothing is spent.
/proc/confirms(text, keeps = WAIT_KEEPS_DEFAULT)
	return part_make(/datum/entry/part/asks, list("type" = /datum/prompt/yes_no, "fields" = list("question" = text), "step" = "confirm", "resume" = CAPTURE, "keeps" = keeps, "confirms" = TRUE))

/// captures(nameof(v), ..., resume = CAPTURE): the fields snapshotted when the op first suspends at an asks() or confirms().
/proc/captures(p1, p2, p3, p4, p5, p6, p7, p8, resume = CAPTURE)
	var/list/names = list()
	for(var/field in list(p1, p2, p3, p4, p5, p6, p7, p8))
		if(istext(field))
			names += field
	return part_make(/datum/entry/part/captures, list("fields" = names, "resume" = resume))

/datum/entry/part/captures
	part_name = "captures"
	stages = PART_STAGE_WAIT

// ---- costs, cooldown, consumes ----

/// costs(RES_X, n): reserves n of a resource after the last answer, commits after the effects. costs(RES_X, +n) is written costs(RES_X, n, add = TRUE).
/proc/costs(resource, n = 1, add = FALSE)
	return part_make(/datum/entry/part/costs, list("resource" = resource, "n" = n, "add" = add))

/datum/entry/part/costs
	part_name = "costs"
	stages = PART_STAGE_REQUIRE | PART_STAGE_DO

/// cooldown(t): the op can run again t deciseconds after it commits.
/proc/cooldown(t)
	return part_make(/datum/entry/part/cooldown, list("t" = t))

/datum/entry/part/cooldown
	part_name = "cooldown"
	stages = PART_STAGE_REQUIRE | PART_STAGE_DO

/// consumes(): uses up the held item (or the one item(T) matched) at commit.
/proc/consumes()
	return part_make(/datum/entry/part/consumes)

/datum/entry/part/consumes
	part_name = "consumes"
	stages = PART_STAGE_REQUIRE | PART_STAGE_DO

// ---- Do: chance and effects ----

/// chance(p, otherwise = parts) and then(PROC_REF(x), checks = ...) are E4's constructors (code/engine/actions/hooks.dm); an op folds their entries into the
/// parts below (op_plan_fold). The failed roll's feedback is `otherwise`: parts that play when chance() fails.

/datum/entry/part/chance
	part_name = "chance"
	stages = PART_STAGE_DO

/// An effect: runs in declaration order in Do and reports an OP_* value.
/datum/entry/part/effect
	part_name = "effect"
	stages = PART_STAGE_DO

/datum/entry/part/effect/then
	part_name = "then"

/// toggles(KEY, when =): flips a tracked boolean var (nameof(v)) or a capability state key on the holder; with `when`, the op exists only while it holds.
/proc/toggles(key, when = null)
	return part_make(/datum/entry/part/effect/toggles, list("key" = key, "when" = when))

/datum/entry/part/effect/toggles
	part_name = "toggles"

/// sets(KEY, v): writes a tracked var or capability state key.
/proc/sets(key, value)
	return part_make(/datum/entry/part/effect/sets, list("key" = key, "value" = value))

/datum/entry/part/effect/sets
	part_name = "sets"

/// holds(STAT_X, v, lasts =, on =, source =, outlives =, bound =): a stat hold on the selected entity.
/proc/holds(stat_id, value = null, lasts = null, on = ON_TARGET, source = null, outlives = FALSE, bound = FALSE)
	return part_make(/datum/entry/part/effect/holds, list("stat" = stat_id, "value" = value, "lasts" = lasts, "on" = on, "source" = source, "outlives" = outlives, "bound" = bound))

/datum/entry/part/effect/holds
	part_name = "holds"

/// releases(STAT_X, on =, source =): releases the op's hold on the stat.
/proc/releases(stat_id, on = ON_TARGET, source = null)
	return part_make(/datum/entry/part/effect/releases, list("stat" = stat_id, "on" = on, "source" = source))

/datum/entry/part/effect/releases
	part_name = "releases"

/// toggles_hold(STAT_X, v, on =, source =): releases the source's hold if it has one, places it otherwise.
/proc/toggles_hold(stat_id, value = null, on = ON_TARGET, source = null)
	return part_make(/datum/entry/part/effect/toggles_hold, list("stat" = stat_id, "value" = value, "on" = on, "source" = source))

/datum/entry/part/effect/toggles_hold
	part_name = "toggles_hold"

/// grants(what, lasts =, on =, source =, outlives =, bound =): grants a capability to the selected entity.
/proc/grants(what, lasts = null, on = ON_TARGET, source = null, outlives = FALSE, bound = FALSE)
	return part_make(/datum/entry/part/effect/grants, list("what" = what, "lasts" = lasts, "on" = on, "source" = source, "outlives" = outlives, "bound" = bound))

/datum/entry/part/effect/grants
	part_name = "grants"

/// put_in(slot): inserts the held item (or the units a stack(T, n) binding reserved) into a slot of the target.
/proc/put_in(slot_id)
	return part_make(/datum/entry/part/effect/put_in, list("slot" = slot_id))

/datum/entry/part/effect/put_in
	part_name = "put_in"
	stages = PART_STAGE_REQUIRE | PART_STAGE_DO

/// take_out(slot): takes the contents of a slot out to the actor's hand or the floor.
/proc/take_out(slot_id)
	return part_make(/datum/entry/part/effect/take_out, list("slot" = slot_id))

/datum/entry/part/effect/take_out
	part_name = "take_out"
	stages = PART_STAGE_REQUIRE | PART_STAGE_DO

/// fixes(): repairs the holder (its integrity goes to the maximum).
/proc/fixes()
	return part_make(/datum/entry/part/effect/fixes)

/datum/entry/part/effect/fixes
	part_name = "fixes"

/// becomes(T): the holder is replaced by a new T.
/proc/becomes(new_type)
	return part_make(/datum/entry/part/effect/becomes, list("type" = new_type))

/datum/entry/part/effect/becomes
	part_name = "becomes"

/// spawns(T, n): adds n of T where the holder is.
/proc/spawns(spawn_type, n = 1)
	return part_make(/datum/entry/part/effect/spawns, list("type" = spawn_type, "n" = n))

/datum/entry/part/effect/spawns
	part_name = "spawns"

/// opens_ui(): opens the holder's window for the actor.
/proc/opens_ui()
	return part_make(/datum/entry/part/effect/opens_ui)

/datum/entry/part/effect/opens_ui
	part_name = "opens_ui"

/// passes(): lets the next candidate run after this one commits.
/proc/passes()
	return part_make(/datum/entry/part/passes)

/datum/entry/part/passes
	part_name = "passes"
	stages = PART_STAGE_MATCH

/// shares_effects(key): runs another op's Require and effects in this act (no Match, no Wait, none of its costs, no asks()).
/proc/shares_effects(key)
	return part_make(/datum/entry/part/effect/shares_effects, list("key" = key))

/datum/entry/part/effect/shares_effects
	part_name = "shares_effects"

/// undone(PROC_REF(x)): runs when a state-graph stage is undone.
/proc/undone(handler)
	return part_make(/datum/entry/part/undone, list("handler" = handler))

/datum/entry/part/undone
	part_name = "undone"

// ---- feedback ----

/// says(msg_type | self, others =, blind =): the message the actor and onlookers get on commit.
/proc/says(msg_type, others = null, blind = null)
	return part_make(/datum/entry/part/says, list("msg" = msg_type, "others" = others, "blind" = blind))

/datum/entry/part/says
	part_name = "says"
	stages = PART_STAGE_DO

/// begins(msg_type | PROC_REF(x), others =, blind =): the message the actor and onlookers get when the op starts its first wait (the one who begins to
/// inject someone is seen to), where says() is what they get when it commits. Like says(), the msg may be a proc that answers the message type.
/proc/begins(msg_type, others = null, blind = null)
	return part_make(/datum/entry/part/begins, list("msg" = msg_type, "others" = others, "blind" = blind))

/datum/entry/part/begins
	part_name = "begins"
	stages = PART_STAGE_WAIT

/// plays(SFX): the sound on commit.
/proc/plays(sfx)
	return part_make(/datum/entry/part/plays, list("sfx" = sfx))

/datum/entry/part/plays
	part_name = "plays"
	stages = PART_STAGE_DO

/// verbs(you, they): the verb pair messages use.
/proc/verbs(you, they)
	return part_make(/datum/entry/part/verbs, list("you" = you, "they" = they))

/datum/entry/part/verbs
	part_name = "verbs"
	stages = PART_STAGE_DO

/// flash(look_layer): a look layer flashed on commit.
/proc/flash(look_layer)
	return part_make(/datum/entry/part/flash, list("layer" = look_layer))

/datum/entry/part/flash
	part_name = "flash"
	stages = PART_STAGE_DO

/// logs(LOG_GAME | LOG_ADMIN): writes the op's log line on commit.
/proc/logs(log_type = LOG_GAME)
	return part_make(/datum/entry/part/logs, list("type" = log_type))

/datum/entry/part/logs
	part_name = "logs"
	stages = PART_STAGE_DO

/// delayed(t, parts...): more parts, run later on the holder's clock with only the holder and the three snapshot names.
/proc/delayed(t, ...)
	return part_make(/datum/entry/part/delayed, list("t" = t), entry_flatten(args.Copy(2)))

/datum/entry/part/delayed
	part_name = "delayed"
	stages = PART_STAGE_DO

/// silent_wait(): the op's wait() draws no progress bar (an op whose wait is not a visible action). Without it a timed wait shows the actor a bar and onlookers a cog.
/proc/silent_wait()
	return part_make(/datum/entry/part/silent_wait)

/datum/entry/part/silent_wait
	part_name = "silent_wait"
	stages = PART_STAGE_WAIT

/// on_interrupt(PROC_REF(x)): x(datum/act/op/A) runs when the op's wait or question is broken before the effects (a keep broke, a requirement refused, the
/// answerer said no or ran out of time), with the reason in A.reason and the actor, holder and held item still named. It does not run when the op is
/// refused before it waits, when it completes, or when its holder or target is gone. A cleanup, never a second try: nothing was spent.
/proc/on_interrupt(handler)
	return part_make(/datum/entry/part/on_interrupt, list("handler" = handler))

/datum/entry/part/on_interrupt
	part_name = "on_interrupt"
	stages = PART_STAGE_WAIT

/// quiet(): no op_done notice.
/proc/quiet()
	return part_make(/datum/entry/part/quiet)

/datum/entry/part/quiet
	part_name = "quiet"
	stages = PART_STAGE_DO

/// claims(): while the op waits (a wait() step), its target is claimed: a second claiming op on the same target is refused (/datum/msg/op/claimed)
/// instead of starting, and op_claimed(target) answers TRUE so the target can draw the work (a door being pried shows its prying sprite).
/// The claim ends with the wait, however it ends.
/proc/claims()
	return part_make(/datum/entry/part/claims)

/datum/entry/part/claims
	part_name = "claims"
	stages = PART_STAGE_WAIT

/// req_unclaimed(because =): no claiming op is waiting on the holder (an op without claims() of its own that must not run over one that does).
/proc/req_unclaimed(because = null)
	return part_make(/datum/entry/part/req/unclaimed, list("because" = because))

/datum/entry/part/req/unclaimed
	part_name = "req_unclaimed"
	default_reason = /datum/msg/op/claimed

/datum/entry/part/req/unclaimed/holds(datum/act/op/A)
	return !op_claimed(A.holder)

// ---- metadata ----

/// label("Text"): the op's menu name.
/proc/label(text)
	return part_make(/datum/entry/part/label, list("text" = text))

/datum/entry/part/label
	part_name = "label"

/// priority(OP_PRIORITY_X | above(key) | below(key)): where the op sits among candidates.
/proc/priority(value)
	return part_make(/datum/entry/part/priority, list("value" = value))

/datum/entry/part/priority
	part_name = "priority"

/// above(key): just above the named op, whatever the tiers.
/proc/above(key)
	return list("above", key)

/// below(key): just below the named op.
/proc/below(key)
	return list("below", key)

/// tag(T): a TAG_X the op carries; extend(TAG_X, ...) reaches it.
/proc/tag(tag_id)
	return part_make(/datum/entry/part/tag, list("tag" = tag_id))

/datum/entry/part/tag
	part_name = "tag"

/// replaces(parts...): inside an extend, swaps the op's effect list for these parts.
/proc/replaces(...)
	return part_make(/datum/entry/part/replaces, null, entry_flatten(args))

/datum/entry/part/replaces
	part_name = "replaces"

/// A bundle: force_pry() and component_swap() are procs returning a list of parts (entry_flatten() flattens them).

// ---- the tool profiles (TOOL_PROFILE, section 9): the defaults tool(Q) brings, per slot ----

/// The parts tool(Q) expands to as defaults: wait, sound, verbs and costs. An op's own wait(), plays(), verbs() or costs(RES_X, n) replaces that slot.
/proc/tool_profile_parts(quality)
	switch(quality)
		if(TOOL_CROWBAR)
			return list(wait(2 SECONDS), verbs("pry", "pries"))
		if(TOOL_SCREWDRIVER)
			return list(wait(2 SECONDS), verbs("screw", "unscrew"))
		if(TOOL_WRENCH)
			return list(wait(2 SECONDS), verbs("wrench", "wrenches"))
		if(TOOL_WIRECUTTER)
			return list(wait(2 SECONDS), verbs("cut", "cuts"))
		if(TOOL_MULTITOOL)
			return list(wait(5 SECONDS), verbs("pulse", "pulses"))
		if(TOOL_WELDER)
			return list(wait(3 SECONDS), verbs("weld", "unweld"), costs(RES_FUEL, 1))
	return list()

// ---- windows ----

/// interface(window, title =, rights =, host =, input = hand(), state =): the window an entity opens. Declaring it adds the open op ("ui_open"), bound to
/// the input and to remote() at the lowest tier: what a type does when nothing more specific answers. `state` is the tgui state the window uses (who may see
/// and use it): `nameof(GLOB.tgui_physical_state)`, the name of a state global (read when the window opens, so the declaration never depends on the global init
/// order), or a /datum/tgui_state; `rights` (an R_* mask, at least one of them) with no state is ADMIN_STATE(rights). Neither: the default state, or the
/// host's own `tgui_window_state` var / `ui_rights` (interface_state() in code/datums/sys/ui.dm). A state that depends on the instance stays a
/// tgui_state() override. `forwards` (nameof(var): a var of the holder that holds the datum, or a list of them) is where a window action the holder has no
/// op for goes: the sleeper console's window is its sleeper's panel, so every button of it is an op of the sleeper (the old UI_ACT_FORWARD). The target's
/// op answers as if its own window sent the button; the actor's reach to the target is not asked (a window's ops have none).
/// `window_var` (nameof(var)) names the window from a var of the host when each subtype sets its own (a module's tgui_id; `window` is null then).
/// `autoupdate` refreshes the window every tick, `pinned` keeps it open through "close all windows" (a dedicated skin element: the lobby, a
/// tooltip, the media panel), `preinitialized` opens a window the host already initialized (its ui_window()). `pressed` (PROC_REF(x), `x(mob/actor, action)`)
/// runs on the holder for every button pressed in its window, its own ops' and the forwarded ones alike, before the op: the PDA's click and fingerprint.
/// `observe` (TRUE) adds the read-only view for a ghost: the op "ui_observe", bound to observer() (by(AFF_OBSERVE): only a ghost provides it), which opens the same
/// window for the observer. The observer's tgui state is update-only, so the ghost sees the data and no button of it reaches an op. Requirements the window's ops share
/// (a broken machine shows nothing) are given to it with extend("ui_observe", needs(...)).
/proc/interface(window, title = null, rights = null, host = null, input = null, state = null, forwards = null, window_var = null, autoupdate = FALSE, pinned = FALSE, preinitialized = FALSE, pressed = null, observe = FALSE)
	var/list/declared = list(entry_make("interface", null, list("window" = window, "title" = title, "rights" = rights, "host" = host, "state" = state, "forwards" = forwards, "window_var" = window_var, "autoupdate" = autoupdate, "pinned" = pinned, "preinitialized" = preinitialized, "pressed" = pressed)), 		op("ui_open", inputs(input || hand(), remote()), priority(OP_PRIORITY_DEFAULT), opens_ui()))
	if(observe)
		declared += op("ui_observe", observer(), priority(OP_PRIORITY_DEFAULT), label("View"), opens_ui())
	return declared

/// ui_shape(operating, channels = list_of(row(...))): the declared shape of the window's data. `analyze gen ui_types` reads the declaration from source and
/// writes the TypeScript type of the window (each field's schema range as the doc comment of its field); at runtime the entry carries no data. It is a
/// macro (code/__defines/engine/declare.dm) so that a field can be written `name = schema`, which no proc taking `...` accepts as a named argument.
