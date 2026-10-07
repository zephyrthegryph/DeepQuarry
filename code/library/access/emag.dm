// The emag capability (doc/rewrite/final_api.html, section 11 "The library": emag(parts..., disables_for =, repeatable =)).
//
// A cryptographic sequencer used on the holder subverts it. State key EMAG_EMAGGED. One op, emag.use, bound to the card, at the highest tier
// (OP_PRIORITY_SUBVERT: subverting comes before anything else a card could do). The parts the type passes are the effect: a wait before it,
// a sets(), a then(PROC_REF(on_emag)); the library adds what every emag shares around them: the card must have a use left, the holder must have
// power (powered = FALSE drops that gate) and must not be subverted already (one-shot, the default; repeatable = TRUE drops that gate), and when the parts went through the key is set, the user is
// told `say`, and the card pays its use.
//
//   emag(then(PROC_REF(on_emag)))                              one-shot
//   emag(then(PROC_REF(on_emag)), repeatable = TRUE)           a card can subvert it again
//   emag(list(wait(0.6 SECONDS), sets(LOCK_LOCKED, FALSE)), say = MSG(apc/emagged))
//
// An effect that must refuse (a door that is open cannot be emagged shut) is a requirement: extend("emag.use", needs(...)).

/// Both native state and the legacy generic capability bit are genuine subversion storage.
/proc/is_emagged(atom/A)
	READS_FROM(A)
	return !!(capability_bits(A) & CAP_EMAGGED) || (cap_of(A, CAP_EMAG) && emag_emagged(A)) // a converted holder keeps it as a capability key
MSG_DEF_SELF(emag/no_charge, "That has no uses left.")
MSG_DEF_SELF(emag/already, "It is already subverted.")
MSG_DEF(emag/done, "You subvert %T% with %I%.", "%U% subverts %T% with %I%.")
MSG_DEF_SELF(emag/emagged_examine, "Its circuits look scorched.")

CAPABILITY_TYPE(emag, CAP_EMAG, /datum/capability/lib/emag, key = NONE, parts = null, say = null, disables_for = null, repeatable = FALSE, powered = TRUE)
cap_keys(CAP_EMAG, EMAGGED = MSG(emag/already))

/datum/capability/lib/emag

/datum/capability/lib/emag/entries()
	var/list/use = list(op("use", item(/obj/item/card/emag), priority(OP_PRIORITY_SUBVERT), \
		needs(req_emag_card()), parts, then(CAP_PROC(finish)), logs(LOG_ADMIN)))
	// The same subversion with no card in hand: what emag_target() (an event, a changeling's pick, a spirit) reaches by key.
	use += op("subvert", ai(), parts, then(CAP_PROC(finish)), logs(LOG_ADMIN))
	// The library default: the card works on a holder that has power (powered = FALSE: one that needs none) and that nobody subverted yet
	// (emagged, or hacked another way: is_subverted()); repeatable = TRUE drops the second.
	if(powered)
		use += extend("emag.use", needs(req_operable()))
	if(!repeatable)
		use += extend("emag.use", needs(req_not_subverted(because = MSG(emag/already))))
		use += extend("emag.subvert", needs(req_not_subverted(because = MSG(emag/already))))
	return use

/// The part of an emag every holder shares, after the type's parts went through: subverted, told, the card paid.
/datum/capability/lib/emag/proc/finish(datum/act/op/A)
	key_set(A.holder, EMAG_EMAGGED, TRUE)
	if(disables_for)
		hold(A.holder, STAT_OPERABLE, FALSE, A.holder, disables_for)
	var/datum/msg/spoken = say || /datum/msg/emag/done
	if(A.actor)
		act_message_t(A.actor, istype(A.holder, /atom) ? A.holder : null, spoken, A.held)
	var/obj/item/card/emag/card = A.held
	if(istype(card))
		card.uses--
		if(card.uses < 1)
			card.spent(A.actor)
	return OP_OK

/// The card has a use left.
/proc/req_emag_card()
	return part_make(/datum/entry/part/req/emag_card)

/datum/entry/part/req/emag_card
	part_name = "req_emag_card"
	default_reason = /datum/msg/emag/no_charge

/datum/entry/part/req/emag_card/holds(datum/act/op/A)
	var/obj/item/card/emag/card = A.held
	return istype(card) && card.can_emag(A.actor)

/// Is this atom subverted (emagged, or taken over another way: an AI hack adds it by overriding is_subverted())? The requirement
/// of the controls a hijacked machine refuses.
/proc/req_not_subverted(because = null)
	return part_make(/datum/entry/part/req/not_subverted, list("because" = because))

/datum/entry/part/req/not_subverted
	part_name = "req_not_subverted"
	default_reason = /datum/msg/req_subverted

/datum/entry/part/req/not_subverted/holds(datum/act/A)
	var/atom/holder = A.holder
	return !istype(holder) || !holder.is_subverted()

/datum/entry/part/req/not_subverted/read_keys(datum/act/op/A)
	return A.holder ? list(list(A.holder, "capkey:[EMAG_EMAGGED]")) : list()
