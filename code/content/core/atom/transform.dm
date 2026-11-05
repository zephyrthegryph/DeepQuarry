





/// Clear the atom's tf_* variables and the current transform state.
/atom/proc/ClearTransform()
	STATE_SET(src, tf_xform, tf_scale_x, null)
	STATE_SET(src, tf_xform, tf_scale_y, null)
	STATE_SET(src, tf_xform, tf_rotation, null)
	STATE_SET(src, tf_xform, tf_offset_x, null)
	STATE_SET(src, tf_xform, tf_offset_y, null)
	transform = null


/// Sets the atom's tf_* variables and the current transform state, also applying others if supplied.
/atom/proc/SetTransform(
	scale,
	scale_x = STATE_PEEK(src, tf_xform, tf_scale_x),
	scale_y = STATE_PEEK(src, tf_xform, tf_scale_y),
	rotation = STATE_PEEK(src, tf_xform, tf_rotation),
	offset_x = STATE_PEEK(src, tf_xform, tf_offset_x),
	offset_y = STATE_PEEK(src, tf_xform, tf_offset_y),
	list/others
)
	if (!isnull(scale))
		STATE_SET(src, tf_xform, tf_scale_x, scale)
		STATE_SET(src, tf_xform, tf_scale_y, scale)
	else
		STATE_SET(src, tf_xform, tf_scale_x, scale_x)
		STATE_SET(src, tf_xform, tf_scale_y, scale_y)
	STATE_SET(src, tf_xform, tf_rotation, rotation)
	STATE_SET(src, tf_xform, tf_offset_x, offset_x)
	STATE_SET(src, tf_xform, tf_offset_y, offset_y)
	transform = matrix().Update(
		scale_x = STATE_PEEK(src, tf_xform, tf_scale_x),
		scale_y = STATE_PEEK(src, tf_xform, tf_scale_y),
		rotation = STATE_PEEK(src, tf_xform, tf_rotation),
		offset_x = STATE_PEEK(src, tf_xform, tf_offset_x),
		offset_y = STATE_PEEK(src, tf_xform, tf_offset_y),
		others = others
	)
