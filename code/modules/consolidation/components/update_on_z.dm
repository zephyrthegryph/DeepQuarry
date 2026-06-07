// Per-atom list of images to update when the atom changes z-level.
// Component-backed, sparse. Global helpers to avoid proc-table bloat.
/datum/component/update_on_z
	dupe_mode = COMPONENT_DUPE_UNIQUE
	var/list/image/images

/datum/component/update_on_z/Initialize()
	. = ..()
	images = list()

/datum/component/update_on_z/Destroy(force)
	images = null
	return ..()

/proc/dq_add_z_update_image(atom/a, image/img)
	if(!img)
		return
	var/datum/component/update_on_z/c = a.GetComponent(/datum/component/update_on_z)
	if(!c)
		c = a.AddComponent(/datum/component/update_on_z)
	c.images |= img

/proc/dq_remove_z_update_image(atom/a, image/img)
	if(!img)
		return
	var/datum/component/update_on_z/c = a.GetComponent(/datum/component/update_on_z)
	if(!c)
		return
	c.images -= img
	if(!c.images.len)
		qdel(c)
