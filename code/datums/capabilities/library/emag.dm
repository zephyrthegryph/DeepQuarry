// The emag capability (doc/rewrite/dx_conventions.md §2). State: CAP_EMAGGED. A cryptographic
// sequencer used on the holder calls `effect` on the holder, (mob/user, obj/item/card/emag/card), then
// spends one of its uses, sets the bit and tells the user `say` (act_message tokens); an effect that
// returns EMAG_DECLINED spends nothing and sets nothing. EMAG_ONCE refuses a
// second swipe with already_say. Draws nothing and gates nothing. Accessor: is_emagged().
//
//	. += emag(say = "You short out %T%'s access lock.", effect = PROC_REF(on_emag))

/datum/capability/emag
	var/say
	var/effect
	var/mode = EMAG_ONCE
	var/already_say

/// An emag: `say` to the user, `effect` (a proc on the holder) run, once or every time (`mode`).
/proc/emag(say, effect, mode = EMAG_ONCE, already_say = "It is already emagged.", log = LOG_ADMIN)
	var/datum/capability/emag/C = new
	C.say = say
	C.effect = effect
	C.mode = mode
	C.already_say = already_say
	C.log = log
	return C

/datum/capability/emag/interactions(atom/holder)
	var/datum/capability/entry/wrapper = use_on("Emag", /obj/item/card/emag, TYPE_PROC_REF(/atom, cap_emag_use), works_unpowered = TRUE, log = log, priority = 50)
	return list(own_entry(wrapper, id = "emag"))

/atom/proc/cap_emag_use(mob/user, obj/item/held)
	var/datum/capability/emag/C = cap_of(src, /datum/capability/emag)
	var/obj/item/card/emag/card = held
	if(!istype(card) || !card.can_emag(user))
		return refuse(user, "[held] has no uses left.")
	if(C.mode == EMAG_ONCE && is_emagged(src))
		return refuse(user, C.already_say)
	// An effect that returns EMAG_DECLINED took nothing this time (a door that is already open):
	// no use is spent and the bit stays as it was.
	if(C.effect && call(src, C.effect)(user, card) == EMAG_DECLINED)
		return TRUE
	cap_set(src, CAP_EMAGGED, TRUE)
	if(C.say)
		act_message(user, src, self = span_warning(C.say), item = card)
	// One use, as /obj/item/card/emag/proc/spend() pays it; the dispatcher writes the log line.
	card.uses--
	if(card.uses < 1)
		card.spent(user)
	return TRUE
