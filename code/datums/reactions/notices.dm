// Notices every atom can publish (doc/rewrite/reactions.md, "Notices"). A type listens with
// on_notice(/datum/notice/shoes_step, PROC_REF(x)) in its reactions(); nothing is allocated unless something
// listens (PUBLISH checks WANTS). They are occurrences: ordered, never coalesced.

/// The wearer of these shoes took a step (published by human handle_footstep()).
/datum/notice/shoes_step
	var/mob/living/carbon/human/wearer
	var/m_intent

/datum/notice/shoes_step/fill(mob/living/carbon/human/wearer, m_intent)
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	src.wearer = wearer
	src.m_intent = m_intent
