/// getFlatIcon asks whether a state has more than its south frame. For a file that is answered from its DMI metadata instead of by building three
/// icons and listing their states; both must agree for every state, directional or not.
/datum/unit_test/dq_icon_state_directions_match_the_icon

/datum/unit_test/dq_icon_state_directions_match_the_icon/Run()
	var/list/files = list('icons/effects/effects.dmi', 'icons/mob/AI.dmi', 'icons/obj/ammo.dmi')
	var/checked = 0
	var/directional = 0
	var/list/wrong = list()
	for(var/file in files)
		for(var/state in icon_states(file))
			if(checked > 400)
				break
			var/slow = (length(icon_states(icon(file, state, NORTH))) || length(icon_states(icon(file, state, EAST))) || length(icon_states(icon(file, state, WEST)))) ? TRUE : FALSE
			var/fast = icon_state_has_directions(file, state) ? TRUE : FALSE
			checked++
			if(slow)
				directional++
			if(slow != fast)
				wrong += "[file]:[state] (slow [slow], metadata [fast])"
	TEST_ASSERT(directional > 0 && directional < checked, "the sample has both directional and single-frame states ([directional] of [checked])")
	TEST_ASSERT_EQUAL(length(wrong), 0, "states whose directions the metadata gets wrong: [jointext(wrong, "; ")]")
