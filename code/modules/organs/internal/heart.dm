/obj/item/organ/internal/heart
	name = "heart"
	icon_state = "heart-on"
	organ_tag = O_HEART
	parent_organ = BP_TORSO
	dead_icon = "heart-off"

	var/standard_pulse_level = PULSE_NORM	// We run on a normal clock. This is NOT CONNECTED to species heart-rate modifier.

/obj/item/organ/internal/heart/handle_germ_effects(cycles)
	. = ..() //Up should return an infection level as an integer
	if(!.) return

	//Endocarditis (very rare, usually for artificially implanted heart valves/pacemakers)
	if (. >= 1)
		if(prob(1))
			owner.custom_pain("Your chest feels uncomfortably tight!",0)
	if (. >= 2)
		if(prob(1))
			owner.custom_pain("A stabbing pain rolls through your chest!",1)
			owner.injure(INJURY_PAIN, 25, parent_organ, src)

/obj/item/organ/internal/heart/robotize()
	..()
	standard_pulse_level = PULSE_NONE

/obj/item/organ/internal/heart/grey
	icon_state = "heart_grey-on"
	dead_icon = "heart_grey-off"


CAPABILITIES(/obj/item/organ/internal/heart/grey/colormatch)
	after_init(0, then(PROC_REF(match_blood_color)))

/// Takes its owner's blood colour, once the body has placed it.
/obj/item/organ/internal/heart/grey/colormatch/proc/match_blood_color(datum/act/timer/A)
	if(ishuman(owner)) // placed in its limb by now
		var/mob/living/carbon/human/H = owner
		color = H.species.blood_color

/obj/item/organ/internal/heart/machine
	name = "hydraulic hub"
	icon_state = "pump-on"
	organ_tag = O_PUMP
	dead_icon = "pump-off"
	robotic = ORGAN_ROBOT

	standard_pulse_level = PULSE_NONE
