/obj/item/pupscrubber
	name = "floor scrubber"
	desc = "Toggles floor scrubbing."
	icon = 'icons/mob/dogborg_vr.dmi'
	icon_state = "scrub0"
	var/enabled = FALSE
	flags = NOBLUDGEON

CAPABILITIES(/obj/item/pupscrubber)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/pupscrubber/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/silicon/robot/R = user
	if(!enabled)
		R.set_scrubbing(TRUE)
		enabled = TRUE
		set_icon_state("scrub1")
	else
		R.set_scrubbing(FALSE)
		enabled = FALSE
		set_icon_state("scrub0")
	return TRUE
