/*
	Alternate Appearances! By RemieRichards
	A framework for replacing an atom (and it's overlays) with an override = 1 image, that's less shit!

	alternate_appearances and viewing_alternate_appearances vars previously
	on /atom are now the lazy alt_appearances_owned and
	alt_appearances_viewing vars (code/datums/sparse_vars/alt_appearance.dm).
	Helpers (dq_get_alt_appearances, etc.) are global procs so we don't bloat
	/atom's proc-table with new instance methods.
*/

/datum/alternate_appearance
	var/key = ""
	var/image/img
	var/list/viewers = list() // ALLOW(instance_list): d: every alternate appearance is shown to someone
	var/tmp/owner_handle

/datum/alternate_appearance/proc/display_to(list/displayTo)
	if(!displayTo || !displayTo.len)
		return
	for(var/mob/M as anything in displayTo)
		var/list/viewing = dq_get_viewing_alt_appearances(M, create = TRUE)
		viewers |= M // ALLOW(object_keyed_lists): hide()/remove() walk viewers to pull the image off each client; a cache null would strand it
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
	if(owner())
		var/list/owned = dq_get_alt_appearances(owner())
		if(owned)
			owned -= key
			if(!owned.len)
				dq_clear_alt_appearances_component(owner())

// it is removed from everyone who saw it.
/datum/alternate_appearance/on_destroy(force)
	remove()
	..()

/atom/proc/add_alt_appearance(key, img, list/displayTo = list())
	if(!key || !img)
		return
	var/list/owned = dq_get_alt_appearances(src, create = TRUE)

	var/datum/alternate_appearance/AA = new()
	AA.img = img
	AA.key = key
	AA.owner_handle = om_handle(src)

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

DECLARE_REF(/datum/alternate_appearance, "img", OWNED, null)

/// LC-refs: the owner this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/alternate_appearance/proc/owner() as /atom
	return om_resolve(owner_handle)
