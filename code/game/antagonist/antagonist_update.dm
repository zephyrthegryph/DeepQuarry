/datum/antagonist/proc/update_leader()
	if(!leader() && length(current_antagonists) && (flags & ANTAG_HAS_LEADER))
		rel_set(src, nameof(leader), LAZYACCESS(current_antagonists, 1))

/datum/antagonist/proc/update_antag_mob(datum/mind/player, preserve_appearance)

	// Get the mob.
	if((flags & ANTAG_OVERRIDE_MOB) && (!player.current || (mob_path && !istype(player.current, mob_path))))
		var/mob/holder = player.current
		rel_set(player, nameof(player.current), new mob_path(get_turf(player.current)))
		player.transfer_to(player.current)
		if(holder) spent(holder)
	rel_set(player, nameof(player.original_character), player.current)
	if(!preserve_appearance && (flags & ANTAG_SET_APPEARANCE))
		after(src, 0.3 SECONDS, PROC_REF(deferred_set_appearance), with = list(player))
	return player.current

/datum/antagonist/proc/deferred_set_appearance(datum/mind/player)
	var/mob/living/carbon/human/H = player.current
	if(istype(H))
		H.change_appearance(APPEARANCE_ALL, H, species_whitelist = valid_species, state = GLOB.tgui_self_state)

/datum/antagonist/proc/update_access(mob/living/player)
	for(var/obj/item/card/id/id in contents_of(player))
		player.set_id_info(id)

/datum/antagonist/proc/clear_indicators(datum/mind/recipient)
	if(!recipient.current || !recipient.current.client)
		return
	for(var/image/I in recipient.current.client.images)
		if(I.icon_state == antag_indicator || (faction_indicator && I.icon_state == faction_indicator))
			spent(I)

/datum/antagonist/proc/get_indicator(datum/mind/recipient, datum/mind/other)
	if(!antag_indicator || !other.current || !recipient.current)
		return
	var/indicator = (faction_indicator && (other in faction_members)) ? faction_indicator : antag_indicator
	var/image/returnimage = image('icons/mob/mob.dmi', loc = other.current, icon_state = indicator)
	returnimage.plane = PLANE_LIGHTING_ABOVE
	return returnimage

/datum/antagonist/proc/update_all_icons()
	if(!antag_indicator)
		return
	for(var/datum/mind/antag in current_antagonists)
		clear_indicators(antag)
		if(faction_invisible && (antag in faction_members))
			continue
		for(var/datum/mind/other_antag in current_antagonists)
			if(antag.current && antag.current.client)
				antag.current.client.images |= get_indicator(antag, other_antag)

/datum/antagonist/proc/update_icons_added(datum/mind/player)
	if(!antag_indicator || !player.current)
		return
	deferred_update_icons_added(player)

/datum/antagonist/proc/deferred_update_icons_added(datum/mind/player)
	var/give_to_player = (!faction_invisible || !(player in faction_members))
	for(var/datum/mind/antag in current_antagonists)
		if(!antag.current)
			continue
		if(antag.current.client)
			antag.current.client.images |= get_indicator(antag, player)
		if(!give_to_player)
			continue
		if(player.current.client)
			player.current.client.images |= get_indicator(player, antag)

/datum/antagonist/proc/update_icons_removed(datum/mind/player)
	if(!antag_indicator || !player.current)
		return
	deferred_update_icons_removed(player)

/datum/antagonist/proc/deferred_update_icons_removed(datum/mind/player)
	clear_indicators(player)
	if(player.current && player.current.client)
		for(var/datum/mind/antag in current_antagonists)
			if(antag.current && antag.current.client)
				for(var/image/I in antag.current.client.images)
					if(I.loc == player.current)
						spent(I)

/datum/antagonist/proc/update_current_antag_max()
	cur_max = hard_cap
	if(SSticker && round_mode())
		if(round_mode().antag_tags && (id in round_mode().antag_tags))
			cur_max = hard_cap_round

	if(round_mode().antag_scaling_coeff)

		var/count = 0
		for(var/mob/living/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
			if(M.client)
				count++

		// Minimum: initial_spawn_target
		// Maximum: hard_cap or hard_cap_round
		cur_max = max(initial_spawn_target,min(round(count/round_mode().antag_scaling_coeff),cur_max))
