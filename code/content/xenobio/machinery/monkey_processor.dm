//To help streamline virology work. Would be broken if put in Xenobio so maybe perhaps don't do that.
//Or do. I'm just a dev, not your boss.

/obj/machinery/processor/monkey
	name = "monkey processor"
	desc = "An industrial grinder used to automate the process of monkey recycling."
	monkeys_per_cube = 1

/obj/item/circuitboard/processor/monkey
	name = T_BOARD("monkey processor")
	build_path = /obj/machinery/processor/monkey

/// A monkey processor takes only a dead monkey.
/obj/machinery/processor/monkey/insert_refusal(atom/movable/AM)
	var/mob/living/carbon/human/H = AM
	return (istype(H) && istype(H.species, /datum/species/monkey) && H.stat == DEAD) ? null : msg_reason("\The [src] cannot process \the [AM] at this time.")
