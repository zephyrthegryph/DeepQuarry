/obj/item/clothing/mask/chew
	name = "chew"

EXTEND_INTERACTIONS(/obj/item/clothing/mask/chew, INTERACT_USE("Toggle", PROC_REF(chew_toggle)))

/obj/item/clothing/mask/chew/proc/chew_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, "toggled")

/obj/item/camerabug
	name = "bug"

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/item/camerabug, \
	INTERACT_VERB("Reset", PROC_REF(bug_reset), REQ_IN_INVENTORY), \
)

/obj/item/camerabug/proc/bug_reset(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, "reset")

/obj/item/bad
EXTEND_INTERACTIONS(/obj/item/bad, INTERACT_VERB("Uses held", PROC_REF(bad_verb), REQ_IN_INVENTORY))

/obj/item/bad/proc/bad_verb(mob/user, obj/item/held, datum/interaction/interaction)
	held.name = "x"
