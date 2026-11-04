/datum/objective/cult/sacrifice
	explanation_text = "Conduct a ritual sacrifice for the glory of Nar-Sie."

/datum/objective/cult/sacrifice/find_target()
	var/list/possible_targets = list()
	if(!possible_targets.len)
		for(var/mob/living/carbon/human/player in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
			if(player.mind && !(player.mind in antag_cult()))
				possible_targets += player.mind
	if(possible_targets.len > 0)
		rel_set(src, nameof(target), pick(possible_targets))
	if(target) set_explanation_text("Sacrifice [target.name], the [target.assigned_role]. You will need the sacrifice rune (Hell blood join) and three acolytes to do so.")

/datum/objective/cult/sacrifice/check_completion()
	return (target && antag_cult() && !antag_cult().sacrificed.Find(target))
