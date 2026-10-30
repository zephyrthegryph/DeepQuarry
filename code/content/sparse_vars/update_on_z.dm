// Per-atom list of images to update when the atom changes z-level: a sparse slot (derived state, never saved).
// Global helpers to avoid proc-table bloat.

/// Images re-planed when this atom changes z-level. Unset when none.
sparse(/atom, z_update_images, type = list)

/proc/dq_add_z_update_image(atom/a, image/img)
	if(!img)
		return
	var/list/images = sparse_get(a, z_update_images)
	if(!images)
		images = sparse_set(a, z_update_images, list())
	images |= img

/proc/dq_remove_z_update_image(atom/a, image/img)
	var/list/images = sparse_get(a, z_update_images)
	if(!img || !images)
		return
	images -= img
	if(!length(images))
		sparse_set(a, z_update_images, null)
