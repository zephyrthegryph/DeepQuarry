// The sight system's API (sight.dm): what other folders call.

/// `T`'s directional_opacity changed (or it was made opaque): the Rust opacity layer takes it at the next flush.
/proc/sight_opacity_changed(turf/T)
	SSsight.dirty_turfs[T] = TRUE

/// The turfs a viewer on `center` would see within `range` if `T` blocked sight as `dirs` (its directional_opacity) says instead of as it does now: a door's
/// other state, asked without changing the door. Pending opacity is flushed first; `T`'s real mask is put back before this returns.
/proc/sight_view_turfs_flipped(turf/center, range, turf/T, dirs)
	if(!isturf(center) || !isturf(T))
		return list()
	if(length(SSsight.dirty_turfs))
		SSsight.flush()
	SSsight.views++
	vg_sight_set_cells(list(T.x, T.y, T.z, dirs))
	. = vg_sight_view(center, range)
	vg_sight_set_cells(list(T.x, T.y, T.z, T.directional_opacity))

/// The shape keys (client_glow_shape_key()'s text) of a light on `center` of reach `range` and glow `margin` with each cell of `cells` (a flat list of `x, y, z, dirs`, the tile and
/// the directional_opacity it would have in its other state) read as flipped, one at a time, nearest first: at most `limit` of them, none equal to `skip_key` or to one before it.
/// The flip, the shadowcast and the key are all done in Rust, and the layer is not written. Pending opacity is flushed first.
/proc/sight_twin_keys(turf/center, range, margin, list/cells, skip_key, limit)
	if(!isturf(center) || !length(cells))
		return list()
	if(length(SSsight.dirty_turfs))
		SSsight.flush()
	SSsight.views++
	return vg_sight_twin_keys(center, range, margin, cells, skip_key, limit)

/// The turfs a viewer standing on `center` sees within `range` through the world opacity layer: symmetric shadowcasting
/// in Rust (verdigris/core/src/propagate/view.rs), darkness playing no part. Flushes pending opacity first.
/proc/sight_view_turfs(turf/center, range)
	if(!isturf(center))
		return list()
	if(length(SSsight.dirty_turfs))
		SSsight.flush()
	SSsight.views++
	return vg_sight_view(center, range)
