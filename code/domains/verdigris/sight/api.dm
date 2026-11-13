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

/// The turfs a viewer standing on `center` sees within `range` through the world opacity layer: symmetric shadowcasting
/// in Rust (verdigris/core/src/propagate/view.rs), darkness playing no part. Flushes pending opacity first.
/proc/sight_view_turfs(turf/center, range)
	if(!isturf(center))
		return list()
	if(length(SSsight.dirty_turfs))
		SSsight.flush()
	SSsight.views++
	return vg_sight_view(center, range)
