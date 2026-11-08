// The sight system's API (sight.dm): what other folders call.

/// `T`'s directional_opacity changed (or it was made opaque): the Rust opacity layer takes it at the next flush.
/proc/sight_opacity_changed(turf/T)
	SSsight.dirty_turfs[T] = TRUE

/// The turfs a viewer standing on `center` sees within `range` through the world opacity layer: symmetric shadowcasting
/// in Rust (verdigris/core/src/propagate/view.rs), darkness playing no part. Flushes pending opacity first.
/proc/sight_view_turfs(turf/center, range)
	if(!isturf(center))
		return list()
	if(length(SSsight.dirty_turfs))
		SSsight.flush()
	SSsight.views++
	return vg_sight_view(center, range)
