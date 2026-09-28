// Per-atom list of images to update when the atom changes z-level: a lazy tmp
// list on /atom (derived state, never saved). Global helpers to avoid proc-table bloat.

/atom
	/// Images re-planed when this atom changes z-level. Null when none. Owned:
	/// deleted with the atom (was the update_on_z component's owned list).
	var/tmp/list/image/z_update_images

REF_OWNED_LIST(/atom, "z_update_images")

/proc/dq_add_z_update_image(atom/a, image/img)
	if(!img)
		return
	if(!a.z_update_images)
		a.z_update_images = list()
	a.z_update_images |= img

/proc/dq_remove_z_update_image(atom/a, image/img)
	if(!img || !a.z_update_images)
		return
	a.z_update_images -= img
	if(!length(a.z_update_images))
		a.z_update_images = null
