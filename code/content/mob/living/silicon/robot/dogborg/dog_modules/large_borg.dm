/obj/item/reagent_containers/glass/beaker/large/borg
	var/mob/living/silicon/robot/R
	var/atom/last_robot_loc

CAPABILITIES(/obj/item/reagent_containers/glass/beaker/large/borg)
	setup(PROC_REF(bind_robot))
	ref_one(nameof(last_robot_loc), /atom)
	ref_one(nameof(R), /atom) // Initialize() binds loc.loc: the robot when a module builds it, any place when something else does

/// Binds the robot (or place) holding the module and watches for being moved out of it (setup()).
/obj/item/reagent_containers/glass/beaker/large/borg/proc/bind_robot()
	rel_set(src, nameof(R), loc.loc)
	observe(src, /datum/notice/movable_attempted_move, src, then(PROC_REF(check_loc)))

/obj/item/reagent_containers/glass/beaker/large/borg/proc/check_loc(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/movable_attempted_move/event = A
	var/atom/old_loc = event.old_loc
	if(old_loc == R || old_loc == R.module)
		rel_set(src, nameof(last_robot_loc), old_loc)
	if(!istype(loc, /obj/machinery) && loc != R && loc != R.module)
		if(last_robot_loc)
			forceMove(last_robot_loc)
			rel_clear(src, nameof(last_robot_loc))
		else
			forceMove(R)
		if(loc == R)
			hud_layerise()
