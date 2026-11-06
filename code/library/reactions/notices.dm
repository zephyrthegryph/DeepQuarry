// Notices every atom can publish (doc/rewrite/reactions.md, "Notices"). A type listens with
// on_notice(/datum/notice/shoes_step, PROC_REF(x)) in its reactions(); nothing is allocated unless something
// listens (PUBLISH checks WANTS). They are occurrences: ordered, never coalesced.

/// The wearer of these shoes took a step (published by human handle_footstep()).
ACTION(shoes_step, mob/living/carbon/human/wearer, m_intent, FIXED, notice = /datum/notice/shoes_step)
