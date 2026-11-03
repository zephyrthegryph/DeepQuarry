// Notices that replaced the OM events and are still published with PUBLISH_LEGACY(E, /datum/notice/x, fields...) in fill() order
// (doc/rewrite/reactions.md section 3). Written by hand: the generator (tools/dx/gen_om_notices.py) went with the events. A notice
// leaves this file when its ACTION() declaration replaces it (the declaration generates the notice type with the same fields).

/// examine and living_shield_injury: their fields come from ACTION(examine) and ACTION(living_shield_injury) (PUBLISH delivers at once, so a sender always reads what
/// the handlers wrote); the type still declares read_back because the read_back lint asks every notice a handler writes into for it.
/datum/notice/examine
	read_back = TRUE // the sender reads what the handlers wrote: answered at once, even mid-delivery (reactions.md section 3)

/datum/notice/living_shield_injury
	read_back = TRUE // the sender reads what the handlers wrote: answered at once, even mid-delivery (reactions.md section 3)

/// Notification: the movable changed loc.
/datum/notice/moved
	var/old_loc
	var/direction
	var/forced

/datum/notice/moved/fill(old_loc, direction, forced)
	src.old_loc = old_loc
	src.direction = direction
	src.forced = forced

/// Just before a datum's Destroy() is called: (force), at this point none of the other components chose to interrupt qdel and Destroy will be called
/// Sent to the obj from base of [/datum/reagent/proc/touch_obj]: (datum/reagent/reagent, amount)
/datum/notice/reagent_expose_obj
	var/datum/reagent/reagent
	var/amount

/datum/notice/reagent_expose_obj/fill(reagent, amount)
	src.reagent = reagent
	src.amount = amount

/// Non TG signals: from base of /datum/reagents/proc/handle_reactions(): (list/datum/xform)
/datum/notice/reagents_holder_reacted
	/// The /datum/xform rules that fired in the settle, in the order they first did.
	var/rules

/datum/notice/reagents_holder_reacted/fill(rules)
	src.rules = rules
