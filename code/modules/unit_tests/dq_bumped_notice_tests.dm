// Bumped() overrides moved onto the bump action's notice (on_notice(/datum/notice/bumped, ...)): the bumped thing still answers a walk-in.

/// A mine that records being set off instead of blowing up the test room.
/obj/effect/mine/dq_bump_probe
	var/set_off = FALSE

/obj/effect/mine/dq_bump_probe/explode(obj)
	set_off = TRUE

/// Walking into a mine sets it off through the bump notice; walking over it (Crossed) still does too.
/datum/unit_test/dq_bumped_notice_mine/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/walker = allocate(/mob/living/carbon/human, T)
	var/obj/effect/mine/dq_bump_probe/mine = allocate(/obj/effect/mine/dq_bump_probe, T)
	walker.bump_into(mine)
	TEST_ASSERT(mine.set_off, "a person walking into the mine sets it off")
	var/obj/effect/mine/dq_bump_probe/other = allocate(/obj/effect/mine/dq_bump_probe, T)
	other.Crossed(walker)
	TEST_ASSERT(other.set_off, "a person walking over the mine sets it off")
