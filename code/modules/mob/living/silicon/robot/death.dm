/mob/living/silicon/robot/dust()
	//Delete the MMI first so that it won't go popping out.
	if(mmi)
		qdel(mmi)
	..()

/mob/living/silicon/robot/ash()
	if(mmi)
		qdel(mmi)
	..()

/// Camera and senses follow the stat change (set_stat()); modules react to
/// COMSIG_MOB_DEATH (the belly component ejects its sleeper).
/mob/living/silicon/robot/death(gibbed)
	if(module)
		var/obj/item/gripper/G = locate(/obj/item/gripper) in module
		G?.drop_item()
	remove_robot_verbs()
	SSmobs.report_death(src)
	..(gibbed,"shudders violently for a moment, then becomes motionless, its eyes slowly darkening.")
