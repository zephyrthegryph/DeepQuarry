//To help streamline virology work. Would be broken if put in Xenobio so maybe perhaps don't do that.
//Or do. I'm just a dev, not your boss.

/obj/machinery/processor/monkey
	name = "monkey processor"
	desc = "An industrial grinder used to automate the process of monkey recycling."
	monkeys_per_cube = 1

/obj/item/circuitboard/processor/monkey
	name = T_BOARD("monkey processor")
	build_path = /obj/machinery/processor/monkey

/obj/machinery/processor/monkey/can_insert(atom/movable/AM)
	if(istype(AM, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = AM
		if(!istype(H.species, /datum/species/monkey))
			return FALSE
		if(H.stat != DEAD)
			return FALSE
		return TRUE
	return FALSE
