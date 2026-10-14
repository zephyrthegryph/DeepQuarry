/turf/replace_surface(type)
	return ChangeTurf(type)

/atom/movable/move_for_construction(atom/holder)
	return forceMove(holder)
