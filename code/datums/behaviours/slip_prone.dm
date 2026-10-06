/**
 * Like unlucky, but only has a chance of slipping into someone!
 * A capability hooked on the moved notice, granted by the Slip Prone trait (added_capability).
 */
CAPABILITY_TYPE(slip_prone, CAP_SLIP_PRONE, /datum/capability/slip_prone, key = NONE)
/datum/capability/slip_prone

/datum/capability/slip_prone/entries()
	return list(on_notice(/datum/notice/moved, then(CAP_PROC(slip_step))))

/datum/capability/slip_prone/proc/slip_step(datum/act/A)
	var/atom/movable/our_guy = A.holder

	if(!isliving(our_guy) || isbelly(our_guy.loc))
		return

	var/mob/living/living_guy = our_guy
	if(living_guy.is_incorporeal()) //no being unlucky if you don't even exist on the same plane.
		return

	if(!prob(0.6))
		return

	var/turf/our_guy_pos = get_turf(our_guy)
	if(!our_guy_pos)
		return

	for(var/turf/the_turf as anything in our_guy_pos.AdjacentTurfs(check_blockage = FALSE)) //need false so we can check disposal units
		if(iswall(the_turf))
			continue

		for(var/mob/living/living_mob in the_turf)
			if(living_mob == our_guy || (living_mob.vore_selected == living_guy.vore_selected))
				continue //Don't do anything to ourselves.
			if(living_mob.stat)
				continue
			if(!can_stumble_vore(living_guy, living_mob) && !can_stumble_vore(living_mob, living_guy)) //Works both ways! Either way, someone's getting eaten!
				continue
			living_mob.stumble_into(living_guy) //logic reversed here because the game is DUMB. This means that living_guy is stumbling into the target!
			act_message(living_guy, living_mob, MSG_SELF(span_boldwarning("You lose your balance, slipping into %T%!")), \
				MSG_OTHERS(span_danger("%U% loses their balance and slips into %T%!")))
			return
