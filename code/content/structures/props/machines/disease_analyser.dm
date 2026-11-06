/obj/structure/prop/machine/disease_analyser
	name = "disease analyser"
	desc = "Analyzes diseases to find out information about them!"
	icon = 'icons/obj/virology.dmi'
	icon_state = "analyser"
	var/on = FALSE

CAPABILITIES(/obj/structure/prop/machine/disease_analyser)
	op("toggle", hand(), label("Toggle"), then(PROC_REF(interaction_toggle)))

/obj/structure/prop/machine/disease_analyser/proc/interaction_toggle(datum/act/op/A)
	var/mob/user = A.actor
	if(!on)
		on = TRUE
		act_message(user, src, others = "%U% turns on %T%.")
		set_icon_state("analyser_")
	else
		on = FALSE
		act_message(user, src, others = "%U% turns off %T%.")
		set_icon_state("analyser")

	return TRUE
