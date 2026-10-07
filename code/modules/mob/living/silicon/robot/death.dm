/mob/living/silicon/robot
	death_message = "shudders violently for a moment, then becomes motionless, its eyes slowly darkening."

/mob/living/silicon/robot/dust()
	//Delete the MMI first so that it won't go popping out.
	rel_clear(src, nameof(mmi), OWN_DELETE)
	..()

/mob/living/silicon/robot/ash()
	rel_clear(src, nameof(mmi), OWN_DELETE)
	..()

/// Camera and senses follow the stat change (set_stat()); modules react to
/// /datum/om/event/mob_death (the belly component ejects its sleeper).
/mob/living/silicon/robot/on_death(gibbed)
	. = ..()
	if(module)
		var/obj/item/gripper/G = locate_in_list(module, /obj/item/gripper)
		G?.drop_item()
	remove_robot_verbs()
	SSmobs.report_death(src)

/mob/living/silicon/robot/on_revived(reason, datum/source)
	. = ..()
	add_robot_verbs()
