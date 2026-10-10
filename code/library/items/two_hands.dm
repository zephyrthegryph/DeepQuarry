// two_hands() (doc/rewrite/final_api.html, section 11 "Items"): something heavy enough that lifting it takes both hands.
//
//   CAPABILITIES(/obj/item/storage/laundry_basket, two_hands())
//
// An empty hand on the item is the lift: with no hand to lift with, or the other hand full, the touch is refused and says why; with both free the
// touch goes on (passes()) to the ordinary pickup, which is where the second grip is made.
//
// Ops (all keyed "two_hands.<name>"): lift.

MSG_DEF_SELF(two_hands/no_hands, "You need two hands to pick this up.")
MSG_DEF_SELF(two_hands/other_hand, "You need your other hand to be empty.")

CAPABILITY_TYPE(two_hands, CAP_TWO_HANDS, /datum/capability/lib/two_hands, key = NONE)

/datum/capability/lib/two_hands

/datum/capability/lib/two_hands/entries()
	return list(
		op("lift", hand(), priority(OP_PRIORITY_PART), when(CAP_PROC(empty_handed)), label("Pick up"), \
			needs(req_bool(CAP_PROC(has_hand), because = MSG(two_hands/no_hands)), req_bool(CAP_PROC(other_hand_free), because = MSG(two_hands/other_hand))), passes()))

/datum/capability/lib/two_hands/proc/empty_handed(datum/act/op/A)
	return isnull(A.held)

/// The lifter has the hand to lift with.
/datum/capability/lib/two_hands/proc/has_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		var/obj/item/organ/external/temp = H.get_organ(user.hand ? BP_L_HAND : BP_R_HAND)
		if(!temp)
			return FALSE
	return TRUE

/// The other hand is empty.
/datum/capability/lib/two_hands/proc/other_hand_free(datum/act/op/A)
	return !A.actor.get_inactive_hand()
