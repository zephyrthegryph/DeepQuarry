// Notices every atom can publish (doc/rewrite/reactions.md, "Notices"). A type listens with
// on_notice(/datum/notice/legacy_hit, PROC_REF(x)) in its reactions(); nothing is allocated unless something
// listens (PUBLISH checks WANTS). They are occurrences: ordered, never coalesced.

/// An item was used on the holder and nothing declared answered it (no operation, no interaction): what a
/// "hit" is to a thing that reacts to being struck. Published from /atom/proc/attackby.
/datum/notice/legacy_hit
	/// The mob that used the item.
	var/mob/attacker
	/// The item used.
	var/obj/item/item

/datum/notice/legacy_hit/fill(mob/attacker, obj/item/item)
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	src.attacker = attacker
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	src.item = item

/datum/notice/legacy_hit/reset()
	. = ..()
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	attacker = null
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	item = null

/// The wearer of these shoes took a step (published by human handle_footstep()).
/datum/notice/shoes_step
	var/mob/living/carbon/human/wearer
	var/m_intent

/datum/notice/shoes_step/fill(mob/living/carbon/human/wearer, m_intent)
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	src.wearer = wearer
	src.m_intent = m_intent
