/obj/structure/prop/machine/isolator
	name = "disease isolator"
	desc = "Used to isolate and identify diseases, allowing for comparison with a remote database."
	icon = 'icons/obj/virology.dmi'
	icon_state = "isolator_in"
	var/on = FALSE

CAPABILITIES(/obj/structure/prop/machine/isolator)
	op("toggle", hand(), label("Toggle"), then(PROC_REF(interaction_toggle)))

/obj/structure/prop/machine/isolator/proc/interaction_toggle(datum/act/op/A)
	var/mob/user = A.actor
	if(!on)
		on = TRUE
		act_message(user, src, others = "%U% turns on %T%.")
		set_icon_state("isolator_")
	else
		on = FALSE
		act_message(user, src, others = "%U% turns off %T%.")
		set_icon_state("isolator_in")

	return TRUE
