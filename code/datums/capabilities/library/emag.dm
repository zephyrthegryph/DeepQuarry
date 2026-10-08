// The emag capability (doc/rewrite/dx_conventions.md §2). State: CAP_EMAGGED. A cryptographic
// sequencer used on the holder waits `delay` (the interaction's timed cost, as any tool wait), then
// calls `effect` on the holder, (mob/user, obj/item/card/emag/card), FIRST: it may refuse by returning
// FALSE (or a reason text), and then no bit is set and no use is spent. Otherwise the bit is set, the
// user told `say` (act_message tokens) and one use spent. EMAG_ONCE refuses a second swipe with
// already_say. Draws nothing by default (an emag declared as an op draws the part LOOK_EMAGGED while the holder is closed up) and gates nothing. Accessor: is_emagged().
//
//	. += cap_emag(say = "You short out %T%'s access lock.", effect = PROC_REF(on_emag), needs = req_set(PANEL), delay = 2 SECONDS)

/datum/capability/emag
	var/say
	var/effect
	var/mode = EMAG_ONCE
	var/already_say
	var/delay = 0
	/// TRUE when the emag is declared as an op beside this capability (emag_op(): a holder refines and contracts it
	/// by CAP_EMAG), so the capability contributes no entry of its own.
	var/as_op = FALSE

/// An emag: `effect` (a proc on the holder) runs first and may refuse; then `say` to the user, once or
/// every time (`mode`). `delay`: the wait before the effect. Gating as every library constructor.
/proc/cap_emag(say, effect, mode = EMAG_ONCE, already_say = "It is already emagged.", delay = 0, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log = LOG_ADMIN)
	var/datum/capability/emag/C = new
	C.say = say
	C.effect = effect
	C.mode = mode
	C.already_say = already_say
	C.delay = delay
	return cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/emag/interactions(atom/holder)
	if(as_op)
		return null
	// The op keyed CAP_EMAG, as emag_op()'s: cap_require(CAP_EMAG, ...) contracts it. A card beats any other use of it
	// (OP_PRIORITY_SUBVERT). The wait is the op wait, before the handler runs.
	return list(adopt_entry(lib_op("Emag", GLOBAL_PROC_REF(cap_emag_use), OP_SHAPE_USE_ON, using = /obj/item/card/emag, key = LEGACY_CAP_EMAG, kind = OP_STRUCTURAL, delay = delay, works_broken = FALSE, works_unpowered = TRUE, priority = OP_PRIORITY_SUBVERT), id = "emag"))

/datum/capability/emag/draw(atom/holder, datum/look/look)
	if(as_op)
		look.part(LOOK_EMAGGED, is_emagged(holder) && !(blocked_by & holder.cap_state))

/datum/capability/emag/look_parts()
	return as_op ? list(LOOK_EMAGGED) : null

/proc/cap_emag_use(atom/holder, mob/user, obj/item/held)
	var/datum/capability/emag/C = cap_of_all(holder, /datum/capability/emag)
	var/obj/item/card/emag/card = held
	if(!istype(card) || !card.can_emag(user))
		return refuse(user, "[held] has no uses left.")
	if(C.mode == EMAG_ONCE && is_emagged(holder))
		return refuse(user, C.already_say)
	if(C.effect)
		// The effect decides first: FALSE (or a reason) refuses, and nothing is set or spent.
		var/result = holder_call(holder, C.effect, list(user, card))
		if(istext(result))
			return refuse(user, result)
		if(!isnull(result) && !result)
			return refuse(user, "Nothing happens.")
	cap_set(holder, CAP_EMAGGED, TRUE)
	if(C.say)
		act_message(user, holder, self = span_warning(C.say), item = card)
	// One use, as /obj/item/card/emag/proc/spend() pays it; the dispatcher writes the log line.
	card.uses--
	if(card.uses < 1)
		card.spent(user)
	return TRUE

/**
 * An emag declared as an op (the hatch's emag): list(the emag capability, the op, its contract). The op is keyed
 * CAP_EMAG and its HANDLER is the effect, (mob/user, obj/item/card/emag/card) -> TRUE or a reason text, so
 * `refine(CAP_EMAG, delay = ..., effect = PROC_REF(on_emag))` swaps the wait and the effect and
 * `cap_require(CAP_EMAG, needs = ...)` adds contracts. What every emag shares runs around it: the card must be
 * usable and (EMAG_ONCE) the holder not yet emagged before, and after a successful commit CAP_EMAGGED is set, `say`
 * told and one use spent (committed(), the capability's own after_op reaction, cap_rx()).
 */
/proc/emag_op(say, effect, mode = EMAG_ONCE, already_say = "It is already emagged.", delay = 0, needs, else_say, log = LOG_ADMIN)
	var/datum/capability/emag/C = new
	C.say = say
	C.mode = mode
	C.already_say = already_say
	C.delay = delay
	C.as_op = TRUE
	// req_set / req_clear in `needs` become the op's state gates (their messages: "close the cover first").
	var/list/gate = cap_fold_state_needs(needs)
	cap_gating(C, needs = gate[2] ? req_clear(gate[2]) : null, log = log)
	var/list/pre = list(GLOBAL_PROC_REF(emag_op_ok))
	if(gate[4])
		pre += islist(gate[4]) ? gate[4] : list(gate[4])
	var/datum/capability/entry/op = cap_op("Emag", effect || GLOBAL_PROC_REF(emag_default_effect), using = /obj/item/card/emag, key = LEGACY_CAP_EMAG, action = ACT_USE, kind = OP_STRUCTURAL, delay = delay, priority = OP_PRIORITY_SUBVERT, needs = pre, else_say = else_say, behind = gate[1], blocked_by = gate[2], locked_by = gate[3], log = log)
	return list(C, op)

/datum/capability/emag/reactions()
	. = ..()
	if(as_op)
		. += cap_rx(src, after_op(LEGACY_CAP_EMAG, PROC_REF(committed)))

/// The default effect of an emag op: nothing beyond the shared commit.
/proc/emag_default_effect(atom/holder, mob/user, obj/item/card/emag/card)
	return TRUE

/// needs: the card has a use left and (EMAG_ONCE) the holder isn't already emagged.
/proc/emag_op_ok(mob/user, atom/holder, obj/item/held)
	var/datum/capability/emag/C = cap_of_all(holder, /datum/capability/emag)
	var/obj/item/card/emag/card = held
	if(!istype(card) || !card.can_emag(user))
		return "[held] has no uses left."
	if(C?.mode == EMAG_ONCE && is_emagged(holder))
		return C.already_say
	return TRUE

/// What the user is told when an emag declared as an op goes through on holder: `say`.
/datum/capability/emag/proc/commit_message(atom/holder)
	return say

/// after_op(CAP_EMAG): the emag went through. Sets the bit, tells the user, spends one use as
/// /obj/item/card/emag/proc/spend() does (the dispatcher writes the log line).
/datum/capability/emag/proc/committed(atom/holder, datum/op_ctx/ctx)
	var/obj/item/card/emag/card = ctx.held
	cap_set(holder, CAP_EMAGGED, TRUE)
	var/say_now = commit_message(holder)
	if(say_now)
		act_message(ctx.actor, holder, self = span_warning(say_now), item = card)
	if(istype(card))
		card.uses--
		if(card.uses < 1)
			card.spent(ctx.actor)
