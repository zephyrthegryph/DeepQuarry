/*
Targeted spells (with the exception of dumbfire) select from all the mobs in the defined range
Targeted spells have two useful flags: INCLUDEUSER and SELECTABLE. These are explained in setup.dm
*/


/datum/spell/targeted //can mean aoe for mobs (limited/unlimited number) or one target mob
	var/max_targets = 1 //leave 0 for unlimited targets in range, more for limited number of casts (can all target one guy, depends on target_ignore_prev) in range
	var/target_ignore_prev = 1 //only important if max_targets > 1, affects if the spell can be cast multiple times at one person from one cast


	var/amt_weakened = 0
	var/amt_paralysis = 0
	var/amt_stunned = 0

	var/amt_dizziness = 0
	var/amt_confused = 0
	var/amt_stuttering = 0

		//set to negatives for healing
	var/amt_dam_fire = 0
	var/amt_dam_brute = 0
	var/amt_dam_oxy = 0
	var/amt_dam_tox = 0

	var/amt_eye_blind = 0
	var/amt_eye_blurry = 0

	var/list/compatible_mobs


/datum/spell/targeted/choose_targets(mob/user)
	return gather_targets(user, null)

/datum/spell/targeted/targets_from_answers(mob/user, datum/ask_sequence/spell_cast/asked)
	return gather_targets(user, asked)

/// The living mobs a single-target spell may pick from.
/datum/spell/targeted/proc/single_candidates(mob/user)
	var/list/possible_targets = list()
	var/list/starting_targets
	if(range == -2)
		starting_targets = REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS)
	else
		starting_targets = view_or_range(range, holder(), selection_type)

	for(var/mob/living/M in starting_targets)
		if(!(spell_flags & INCLUDEUSER) && M == user)
			continue
		if(compatible_mobs && length(compatible_mobs))
			if(!is_type_in_list(M, compatible_mobs)) continue
		if(compatible_mobs && length(compatible_mobs) && !is_type_in_list(M, compatible_mobs))
			continue
		possible_targets += M
	return possible_targets

/// The living mobs a multi-target spell may pick from.
/datum/spell/targeted/proc/multi_candidates(mob/user)
	var/list/possible_targets = list()
	var/list/starting_targets

	if(range == -2)
		starting_targets = REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS)
	else
		starting_targets = view_or_range(range, holder(), selection_type)

	for(var/mob/living/target in starting_targets)
		if(!(spell_flags & INCLUDEUSER) && target == user)
			continue
		if(!is_type_in_list(target, compatible_mobs)) // compatible_mobs is lazy; an empty table always rejected, and null still does
			continue
		possible_targets += target
	return possible_targets

/datum/spell/targeted/target_questions(mob/user)
	if(!(spell_flags & SELECTABLE))
		return null
	if(max_targets == 0)
		return null
	if(max_targets == 1)
		if((range == 0 || range == -1) && spell_flags & INCLUDEUSER)
			return null
		if(!length(single_candidates(user)))
			return null
		return list(question_step("target", /datum/prompt/choice, question = "Choose the target for the spell.", title = "Targeting", choices = single_candidates(user)))
	if(!length(multi_candidates(user)))
		return null
	var/list/steps = list()
	for(var/i in 1 to max_targets)
		steps += PROC_REF(ask_next_target)
	return steps

/datum/spell/targeted/casts_picked_on_stop()
	return max_targets != 1 // closing a question of a many-target spell picks no more

/// The mobs picked so far in the multi-target questions before step `upto`.
/datum/spell/targeted/proc/picked_targets(datum/ask_sequence/spell_cast/asked, upto)
	var/list/picked = list()
	for(var/j in 1 to upto - 1)
		var/mob/M = asked.get("target[j]")
		if(!M)
			continue
		if(range != -2 && !(M in view_or_range(range, holder(), selection_type)))
			continue
		picked += M
	return picked

/// A step of the multi-target questions: the next pick, from the mobs not picked yet.
/datum/spell/targeted/proc/ask_next_target(datum/ask_sequence/spell_cast/asked)
	var/i = asked.step_index
	if(i > 1 && isnull(asked.get("target[i - 1]")))
		return ASK_STOP // the caster closed the last question: no more picks
	var/mob/user = asked.actor()
	if(!user)
		return ASK_STOP
	var/list/possible_targets = multi_candidates(user) - picked_targets(asked, i)
	if(!length(possible_targets))
		return null
	var/list/step = question_step("target[i]", /datum/prompt/choice, question = "Choose the target for the spell.", title = "Targeting", choices = possible_targets)
	step["optional"] = TRUE // a closed question picks no more instead of dropping the cast
	return step

/datum/spell/targeted/proc/gather_targets(mob/user, datum/ask_sequence/spell_cast/asked)
	var/list/targets = list()

	if(max_targets == 0) //unlimited
		if(range == -2)
			targets = REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS)
		else
			for(var/mob/living/target in view_or_range(range, holder(), selection_type))
				targets += target

	else if(max_targets == 1) //single target can be picked
		if((range == 0 || range == -1) && spell_flags & INCLUDEUSER)
			targets += user
		else
			var/list/possible_targets = single_candidates(user)

			if(possible_targets.len)
				if(spell_flags & SELECTABLE) //if we are allowed to choose. see setup.dm for details
					var/mob/temp_target = asked?.get("target")
					if(temp_target)
						targets += temp_target
				else
					targets += pick(possible_targets)
			//Adds a safety check post-input to make sure those targets are actually in range.


	else
		var/list/possible_targets = multi_candidates(user)

		if(spell_flags & SELECTABLE)
			for(var/i = 1, i<=max_targets, i++)
				if(!possible_targets.len)
					break
				var/mob/M = asked?.get("target[i]")
				if(!M)
					break // closing a question picks no more
				if(range != -2)
					if(!(M in view_or_range(range, holder(), selection_type)))
						continue
				targets += M
				possible_targets -= M
		else
			for(var/i=1,i<=max_targets,i++)
				if(!possible_targets.len)
					break
				if(target_ignore_prev)
					var/target = pick(possible_targets)
					possible_targets -= target
					targets += target
				else
					targets += pick(possible_targets)

	if(!(spell_flags & INCLUDEUSER) && (user in targets))
		targets -= user

	if(compatible_mobs && length(compatible_mobs))
		for(var/mob/living/target in targets) //filters out all the non-compatible mobs
			if(!is_type_in_list(target, compatible_mobs))
				targets -= target

	return targets

/datum/spell/targeted/cast(list/targets, mob/user)
	for(var/mob/living/target in targets.Copy())
		if(range >= 0)
			if(!(target in view_or_range(range, holder(), selection_type))) //filter at time of casting
				targets -= target
				continue
		apply_spell_damage(target)

/datum/spell/targeted/proc/apply_spell_damage(mob/living/target)
	spell_injure(target, INJURY_BLUNT, amt_dam_brute, list(TREAT_TISSUE_REPAIR, TREAT_PLATING_REPAIR))
	spell_injure(target, INJURY_BURN, amt_dam_fire, list(TREAT_BURN_CARE, TREAT_WIRING_REPAIR))
	spell_injure(target, INJURY_TOXIN, amt_dam_tox, list(TREAT_ANTITOXIN))
	spell_oxygen_debt(target, amt_dam_oxy)
	//disabling
	target.status_at_least(STAT_WEAKENED, amt_weakened)
	target.status_at_least(STAT_PARALYZED, amt_paralysis)
	target.status_at_least(STAT_STUNNED, amt_stunned)
	if(amt_weakened || amt_paralysis || amt_stunned)
		if(target && target?.buckled_to())
			var/atom/movable/_tmp_buck_43 = target?.buckled_to()
			_tmp_buck_43.unbuckle_mob( target, TRUE)
	target.status_at_least(STAT_BLINDED, amt_eye_blind)
	target.status_adjust(STAT_BLURRY, amt_eye_blurry)
	target.status_adjust(STAT_DIZZY, amt_dizziness)
	target.status_at_least(STAT_CONFUSED, amt_confused)
	target.status_adjust(STAT_STUTTERING, amt_stuttering)
