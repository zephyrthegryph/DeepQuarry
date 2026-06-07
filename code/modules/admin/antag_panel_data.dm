// Structured-data counterpart to /datum/antagonist/get_check_antag_output.
//
// The legacy proc returns an HTML blob with embedded byond:// links
// for PP/PM/TP per antagonist member. To make RoundStatusPanel
// fully structured we expose the same info as plain associative
// lists; the React side renders proper components and dispatches
// per-row actions via tgui_act.

/datum/antagonist/proc/get_check_antag_data(datum/admins/requester)
	if(!current_antagonists || !current_antagonists.len)
		return null

	var/list/members = list()
	for(var/datum/mind/player in current_antagonists)
		var/mob/M = player.current
		if(!M)
			members += list(list(
				"key" = player.key,
				"mob_missing" = TRUE,
			))
			continue
		members += list(list(
			"name" = M.real_name,
			"key" = player.key,
			"ref" = "\ref[M]",
			"logged_out" = !M.client,
			"dead" = M.stat == DEAD,
		))

	var/list/disks
	if(flags & ANTAG_HAS_NUKE)
		disks = list()
		for(var/obj/item/disk/nuclear/N in GLOB.nuke_disks)
			disks += list(list(
				"name" = N.name,
				"location" = describe_disk_location(N),
			))

	. = list(
		"role_text" = role_text,
		"role_text_plural" = role_text_plural,
		"members" = members,
	)
	if(disks)
		.["disks"] = disks


// Structured-data counterpart to /datum/antagonist/get_panel_entry.
// Returns a {id, role_text, is_antagonist, has_locations, extra_html}
// associative list describing one antag template row for the Edit
// Memory panel. extra_html is whatever get_extra_panel_options
// returns (it's rare and the per-antag-type options aren't worth
// structuring further at this layer).
/datum/antagonist/proc/get_panel_data(datum/mind/player)
	return list(
		"id" = id,
		"role_text" = role_text,
		"is_antagonist" = !!is_antagonist(player),
		"has_locations" = !!(starting_locations && length(starting_locations)),
		"extra_html" = get_extra_panel_options(player) || "",
	)


/datum/antagonist/proc/describe_disk_location(obj/item/disk/nuclear/N)
	var/atom/disk_loc = N.loc
	var/result = ""
	while(!istype(disk_loc, /turf))
		if(istype(disk_loc, /mob))
			var/mob/M = disk_loc
			result += "carried by [M.real_name] "
		else if(istype(disk_loc, /obj))
			var/obj/O = disk_loc
			result += "in \a [O.name] "
		if(!disk_loc.loc)
			break
		disk_loc = disk_loc.loc
	if(istype(disk_loc, /turf))
		result += "in [disk_loc.loc] at ([disk_loc.x], [disk_loc.y], [disk_loc.z])"
	return result
