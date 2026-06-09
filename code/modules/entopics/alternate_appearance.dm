/*
	Alternate Appearances! By RemieRichards
	A framework for replacing an atom (and it's overlays) with an override = 1 image, that's less shit!

	alternate_appearances and viewing_alternate_appearances vars previously
	on /atom have been moved to /datum/component/alt_appearances_owner and
	/datum/component/alt_appearances_viewer in .../components/.
	Helpers (dq_get_alt_appearances, etc.) are global procs so we don't bloat
	/atom's proc-table with new instance methods.
*/

/datum/alternate_appearance
	var/key = ""
	var/image/img
	var/list/viewers = list()
	var/atom/owner = null


/datum/alternate_appearance/proc/display_to(list/displayTo)
	if(!displayTo || !displayTo.len)
		return
	for(var/mob/M as anything in displayTo)
		var/list/viewing = dq_get_viewing_alt_appearances(M, create = TRUE)
		viewers |= M
		viewing |= src
		if(M.client)
			M.client.images |= img


/datum/alternate_appearance/proc/hide(list/hideFrom)
	var/list/hiding = viewers
	if(hideFrom)
		hiding = hideFrom

	for(var/mob/M as anything in hiding)
		if(M.client)
			M.client.images -= img
		var/list/viewing = dq_get_viewing_alt_appearances(M)
		if(viewing && viewing.len)
			viewing -= src
			if(!viewing.len)
				dq_clear_viewing_alt_appearances_component(M)
		viewers -= M


/datum/alternate_appearance/proc/remove()
	hide()
	if(owner)
		var/list/owned = dq_get_alt_appearances(owner)
		if(owned)
			owned -= key
			if(!owned.len)
				dq_clear_alt_appearances_component(owner)


/datum/alternate_appearance/Destroy()
	remove()
	owner = null
	return ..()


/atom/Destroy()
	. = ..()
	remove_all_alt_appearances()

/atom/proc/add_alt_appearance(key, img, list/displayTo = list())
	if(!key || !img)
		return
	var/list/owned = dq_get_alt_appearances(src, create = TRUE)

	var/datum/alternate_appearance/AA = new()
	AA.img = img
	AA.key = key
	AA.owner = src

	if(owned[key])
		qdel(owned[key])
	owned[key] = AA
	if(displayTo && displayTo.len)
		display_alt_appearance(key, displayTo)


/atom/proc/remove_alt_appearance(key)
	var/list/owned = dq_get_alt_appearances(src)
	if(owned && owned[key])
		qdel(owned[key])

/atom/proc/remove_all_alt_appearances()
	var/list/owned = dq_get_alt_appearances(src)
	if(!owned)
		return
	for(var/key in owned)
		if(owned[key])
			qdel(owned[key])
			owned.Remove(key)
	dq_clear_alt_appearances_component(src)

/atom/proc/display_alt_appearance(key, list/displayTo)
	var/list/owned = dq_get_alt_appearances(src)
	if(!owned || !key)
		return
	var/datum/alternate_appearance/AA = owned[key]
	if(!AA || !AA.img)
		return
	AA.display_to(displayTo)


/atom/proc/hide_alt_appearance(key, list/hideFrom)
	var/list/owned = dq_get_alt_appearances(src)
	if(!owned || !key)
		return
	var/datum/alternate_appearance/AA = owned[key]
	if(!AA)
		return
	AA.hide(hideFrom)
