/obj/structure/prop/machine/centrifuge
	name = "centrifuge"
	desc = "Used to separate things with different weight. Spin 'em round, round, right round."
	icon = 'icons/obj/virology.dmi'
	icon_state = "centrifuge"
	var/on = FALSE

CAPABILITIES(/obj/structure/prop/machine/centrifuge)
	op("toggle", hand(), label("Toggle"), then(PROC_REF(interaction_toggle)))

/obj/structure/prop/machine/centrifuge/proc/interaction_toggle(datum/act/op/A)
	var/mob/user = A.actor
	if(!on)
		on = TRUE
		act_message(user, src, others = "%U% turns on %T%.")
		set_icon_state("centrifuge_moving")
	else
		on = FALSE
		act_message(user, src, others = "%U% turns off %T%.")
		set_icon_state("centrifuge")

	return TRUE
