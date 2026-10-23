





/// Clear the atom's tf_* variables and the current transform state.
/atom/proc/ClearTransform()
	sparse_set(src, tf_scale_x, null)
	sparse_set(src, tf_scale_y, null)
	sparse_set(src, tf_rotation, null)
	sparse_set(src, tf_offset_x, null)
	sparse_set(src, tf_offset_y, null)
	transform = null


/// Sets the atom's tf_* variables and the current transform state, also applying others if supplied.
/atom/proc/SetTransform(
	scale,
	scale_x = sparse_get(src, tf_scale_x),
	scale_y = sparse_get(src, tf_scale_y),
	rotation = sparse_get(src, tf_rotation),
	offset_x = sparse_get(src, tf_offset_x),
	offset_y = sparse_get(src, tf_offset_y),
	list/others
)
	if (!isnull(scale))
		sparse_set(src, tf_scale_x, scale)
		sparse_set(src, tf_scale_y, scale)
	else
		sparse_set(src, tf_scale_x, scale_x)
		sparse_set(src, tf_scale_y, scale_y)
	sparse_set(src, tf_rotation, rotation)
	sparse_set(src, tf_offset_x, offset_x)
	sparse_set(src, tf_offset_y, offset_y)
	transform = matrix().Update(
		scale_x = sparse_get(src, tf_scale_x),
		scale_y = sparse_get(src, tf_scale_y),
		rotation = sparse_get(src, tf_rotation),
		offset_x = sparse_get(src, tf_offset_x),
		offset_y = sparse_get(src, tf_offset_y),
		others = others
	)
