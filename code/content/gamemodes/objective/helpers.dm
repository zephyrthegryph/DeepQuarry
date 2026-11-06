//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

/datum/objective
	var/datum/mind/owner = null			//Who owns the objective.
	var/explanation_text = "Nothing"	//What that person is supposed to do.
	var/datum/mind/target = null		//If they are focused on a particular person.
	var/target_amount = 0				//If they are focused on a particular number. Steal objectives have their own counter.
	var/completed = 0					//currently only used for custom objectives.

REGISTRY_MEMBERSHIP(/datum/objective, REGISTRY_OBJECTIVES)

/datum/objective/New(text)
	join_registries()
	if(text)
		explanation_text = text
	..()

/datum/objective/proc/check_completion()
	return completed

/datum/objective/proc/find_target()
	var/list/possible_targets = list()
	for(var/datum/mind/possible_target in ticker_minds())
		if(possible_target != owner && ishuman(possible_target.current) && (possible_target.current.stat != 2))
			possible_targets += possible_target
	if(possible_targets.len > 0)
		rel_set(src, nameof(target), pick(possible_targets))

/datum/objective/proc/find_target_by_role(role, role_type=0)//Option sets either to check assigned role or special role. Default to assigned.
	for(var/datum/mind/possible_target in ticker_minds())
		if((possible_target != owner) && ishuman(possible_target.current) && ((role_type ? possible_target.special_role : possible_target.assigned_role) == role) )
			rel_set(src, nameof(target), possible_target)
			break

// The mind owns its objectives (mind.objectives, OWN); owner is the one-sided back view.
CAPABILITIES(/datum/objective)
	ref_one(nameof(owner))
	ref_one(nameof(target))
