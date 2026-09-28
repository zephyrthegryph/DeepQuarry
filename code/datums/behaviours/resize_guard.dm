/// Resize guard (was /datum/component/resize_guard). While a mob is at an extreme size
/// allowed only in AREA_ALLOW_LARGE_SIZE areas, moving anywhere else resizes it back
/// within bounds. A shared behaviour singleton on the moved event; the check runs out
/// of the delivery (om_after) because resize() detaches the guard itself.
/datum/om/behaviour/resize_guard
	handles = list(/datum/om/event/moved)

/datum/om/behaviour/resize_guard/on_moved(mob/living/L, datum/om/event/moved/event)
	om_after(L, 0, TYPE_PROC_REF(/mob/living, resize_guard_check))

/mob/living/proc/resize_guard_check()
	if(!om_attached(src, /datum/om/behaviour/resize_guard))
		return
	var/area/A = get_area(src)
	if(A?.flag_check(AREA_ALLOW_LARGE_SIZE))
		return
	om_detach(src, /datum/om/behaviour/resize_guard)
	resize(size_multiplier, ignore_prefs = TRUE)
