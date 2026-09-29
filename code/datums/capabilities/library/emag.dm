// The emag capability (doc/rewrite/dx_conventions.md §2). State: CAP_EMAGGED. A cryptographic
// sequencer used on the holder waits `delay` (the interaction's timed cost, as any tool wait), then
// calls `effect` on the holder, (mob/user, obj/item/card/emag/card), FIRST: it may refuse by returning
// FALSE (or a reason text), and then no bit is set and no use is spent. Otherwise the bit is set, the
// user told `say` (act_message tokens) and one use spent. EMAG_ONCE refuses a second swipe with
// already_say. Draws nothing by default and gates nothing. Accessor: is_emagged().
//
//	. += cap_emag(say = "You short out %T%'s access lock.", effect = PROC_REF(on_emag), behind = PANEL, delay = 2 SECONDS)

/datum/capability/emag
	layer_name = CAP_NO_LAYER
	var/say
	var/effect
	var/mode = EMAG_ONCE
	var/already_say
	var/delay = 0

/// An emag: `effect` (a proc on the holder) runs first and may refuse; then `say` to the user, once or
/// every time (`mode`). `delay`: the wait before the effect. Gating as every library constructor.
/proc/cap_emag(say, effect, mode = EMAG_ONCE, already_say = "It is already emagged.", delay = 0, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log = LOG_ADMIN, layer = CAP_NO_LAYER)
	var/datum/capability/emag/C = new
	C.say = say
	C.effect = effect
	C.mode = mode
	C.already_say = already_say
	C.delay = delay
	C.layer_name = layer
	return cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/emag/interactions(atom/holder)
	var/datum/interaction/capability/E = adopt_entry(cap_use_on("Emag", /obj/item/card/emag, TYPE_PROC_REF(/atom, cap_emag_use), works_unpowered = TRUE, priority = 50), id = "emag")
	E.duration = delay // paid through use_tool() like any timed interaction, before the handler runs
	return list(E)

/datum/capability/emag/draw(atom/holder, datum/look/look)
	draw_layer(look, when = is_emagged(holder))

/atom/proc/cap_emag_use(mob/user, obj/item/held)
	var/datum/capability/emag/C = cap_of_all(src, /datum/capability/emag)
	var/obj/item/card/emag/card = held
	if(!istype(card) || !card.can_emag(user))
		return refuse(user, "[held] has no uses left.")
	if(C.mode == EMAG_ONCE && is_emagged(src))
		return refuse(user, C.already_say)
	if(C.effect)
		// The effect decides first: FALSE (or a reason) refuses, and nothing is set or spent.
		var/result = call(src, C.effect)(user, card)
		if(istext(result))
			return refuse(user, result)
		if(!isnull(result) && !result)
			return refuse(user, "Nothing happens.")
	cap_set(src, CAP_EMAGGED, TRUE)
	if(C.say)
		act_message(user, src, self = span_warning(C.say), item = card)
	// One use, as /obj/item/card/emag/proc/spend() pays it; the dispatcher writes the log line.
	card.uses--
	if(card.uses < 1)
		card.spent(user)
	return TRUE
