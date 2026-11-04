// Notice types that are not declared by an ACTION(): read-back markers and notices built by hand with notice_take().

/// examine and living_shield_injury: their fields come from ACTION(examine) and ACTION(living_shield_injury) (PUBLISH delivers at once, so a sender always reads what
/// the handlers wrote); the type still declares read_back because the read_back lint asks every notice a handler writes into for it.
/datum/notice/examine
	read_back = TRUE // the sender reads what the handlers wrote: answered at once, even mid-delivery (reactions.md section 3)

/datum/notice/living_shield_injury
	read_back = TRUE // the sender reads what the handlers wrote: answered at once, even mid-delivery (reactions.md section 3)

/// Sent to the obj from base of [/datum/reagent/proc/touch_obj]: (datum/reagent/reagent, amount)
/datum/notice/reagent_expose_obj
	var/datum/reagent/reagent
	var/amount

/// Non TG signals: from base of /datum/reagents/proc/handle_reactions(): (list/datum/xform)
/datum/notice/reagents_holder_reacted
	/// The /datum/xform rules that fired in the settle, in the order they first did.
	var/rules
