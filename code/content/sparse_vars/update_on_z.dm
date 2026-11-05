// Per-atom list of images to update when the atom changes z-level: a sparse slot (derived state, never saved).
// Global helpers to avoid proc-table bloat.


/proc/dq_add_z_update_image(atom/a, image/img)
	if(!img)
		return
	var/list/images = STATE_PEEK(a, atom_misc, z_update_images)
	if(!images)
		images = list()
		STATE_SET(a, atom_misc, z_update_images, images)
	images |= img

/proc/dq_remove_z_update_image(atom/a, image/img)
	var/list/images = STATE_PEEK(a, atom_misc, z_update_images)
	if(!img || !images)
		return
	images -= img
	if(!length(images))
		STATE_SET(a, atom_misc, z_update_images, null)
