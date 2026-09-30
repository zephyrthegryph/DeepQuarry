// Notices every atom can publish (doc/rewrite/reactions.md, "Notices"). A type listens with
// on_notice(/datum/notice/hit, PROC_REF(x)) in its reactions(); nothing is allocated unless something
// listens (PUBLISH checks WANTS). They are occurrences: ordered, never coalesced.

/// An item was used on the holder and nothing declared answered it (no operation, no interaction): what a
/// "hit" is to a thing that reacts to being struck. Published from /atom/proc/attackby.
/datum/notice/hit
	/// The mob that used the item.
	var/mob/attacker
	/// The item used.
	var/obj/item/item

/datum/notice/hit/fill(mob/attacker, obj/item/item)
	src.attacker = attacker
	src.item = item

/datum/notice/hit/reset()
	. = ..()
	attacker = null
	item = null

/// A human touched the holder with an empty hand and nothing declared answered it: the claws-out swipe of
/// a shredder. The listener decides whether this attacker can shred it (species.can_shred()). Published
/// from /atom/proc/attack_hand.
/datum/notice/slashed
	var/mob/living/carbon/human/attacker

/datum/notice/slashed/fill(mob/living/carbon/human/attacker)
	src.attacker = attacker

/datum/notice/slashed/reset()
	. = ..()
	attacker = null
