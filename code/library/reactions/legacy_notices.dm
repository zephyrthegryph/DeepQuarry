// Notice types that are not declared by an ACTION(): read-back markers and notices built by hand with notice_take().

/// Sent to the obj from base of [/datum/reagent/proc/touch_obj]: (datum/reagent/reagent, amount)
/datum/notice/reagent_expose_obj
	var/datum/reagent/reagent
	var/amount

/// Non TG signals: from base of /datum/reagents/proc/handle_reactions(): (list/datum/xform)
/datum/notice/reagents_holder_reacted
	/// The /datum/xform rules that fired in the settle, in the order they first did.
	var/rules
