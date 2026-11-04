/obj/structure/prop/machine/incubator
	name = "incubator"
	desc = "Encourages the growth of diseases. This model comes with a dispenser system and a small radiation generator."
	icon = 'icons/obj/virology.dmi'
	icon_state = "incubator"
	var/on = FALSE

CAPABILITIES(/obj/structure/prop/machine/incubator)
	op("toggle", hand(), label("Toggle"), then(PROC_REF(interaction_toggle)))

/obj/structure/prop/machine/incubator/proc/interaction_toggle(datum/act/op/A)
	var/mob/user = A.actor
	if(!on)
		on = TRUE
		act_message(user, src, others = "%U% turns on %T%.")
		set_icon_state("incubator_on")
	else
		on = FALSE
		act_message(user, src, others = "%U% turns off %T%.")
		set_icon_state("incubator")

	return TRUE
