/// Resize guard. While a mob is at an extreme size
/// allowed only in AREA_ALLOW_LARGE_SIZE areas, moving anywhere else resizes it back
/// within bounds. A shared behaviour singleton on the moved event; the check runs out
/// of the delivery (after()) because resize() revokes the guard itself. A capability the mob grants itself (resize()).
CAPABILITY_TYPE(resize_guard, CAP_RESIZE_GUARD, /datum/capability/resize_guard, key = NONE)
/datum/capability/resize_guard

/datum/capability/resize_guard/entries()
	return list(on_notice(/datum/notice/moved, then(CAP_PROC(guard_moved))))

/datum/capability/resize_guard/proc/guard_moved(datum/act/A)
	after(A.holder, 0, TYPE_PROC_REF(/mob/living, resize_guard_check))

/mob/living/proc/resize_guard_check()
	if(!granted(src, /datum/capability/resize_guard))
		return
	var/area/A = get_area(src)
	if(A?.flag_check(AREA_ALLOW_LARGE_SIZE))
		return
	revoke(src, /datum/capability/resize_guard, src)
	resize(size_multiplier, ignore_prefs = TRUE)
