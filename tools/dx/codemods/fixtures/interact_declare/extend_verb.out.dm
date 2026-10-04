/obj/item/clothing/mask/chew
	name = "chew"

CAPABILITIES(/obj/item/clothing/mask/chew)
	op("chew_toggle", in_hand(), label("Toggle"), then(PROC_REF(chew_toggle)))

/obj/item/clothing/mask/chew/proc/chew_toggle(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, "toggled")

/obj/item/camerabug
	name = "bug"

/// Old object verbs.
CAPABILITIES(/obj/item/camerabug)
	op("bug_reset", menu(), label("Reset"), needs(carried()), then(PROC_REF(bug_reset)))

/obj/item/camerabug/proc/bug_reset(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, "reset")

/obj/item/bad
EXTEND_INTERACTIONS(/obj/item/bad, INTERACT_VERB("Uses held", PROC_REF(bad_verb), REQ_IN_INVENTORY))

/obj/item/bad/proc/bad_verb(mob/user, obj/item/held, datum/interaction/interaction)
	held.name = "x"
