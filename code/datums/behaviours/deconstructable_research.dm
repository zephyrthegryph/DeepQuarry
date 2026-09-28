/// Per-object research value for the destructive analyzer (was
/// /datum/component/deconstructable_research). Object state, read directly by
/// techweb_item_point_check() (was COMSIG_TECHWEB_POINT_CHECK / _TYPE_CHECK).
/obj
	///Used by R&D to determine how many points the item gives (0: none).
	var/techweb_points = 0
	///Used by R&D to determine what point type the item gives, if any
	var/techweb_point_type = TECHWEB_POINT_TYPE_GENERIC

/obj/proc/make_deconstructable_research(techweb_points, techweb_point_type)
	if(!isnull(techweb_points))
		src.techweb_points = techweb_points
	if(!isnull(techweb_point_type))
		src.techweb_point_type = techweb_point_type
