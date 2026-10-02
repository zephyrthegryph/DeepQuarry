/datum/Destroy()
/atom/Destroy()
/atom/movable/Destroy()
/client/Destroy()
/datum/proc/Destroy()
/datum/controller/Destroy()
/datum/controller/subsystem/garbage/Destroy()
/datum/controllers/Destroy()
/mob/living/Destroy ()
/mob/living/Destroy
/obj/proc/Destroy()
/obj/foo/proc/Destroy()
	/obj/indented/Destroy()
// /obj/commented/Destroy()
/* /obj/blocked/Destroy() */
/obj/x/DestroyThing()
/obj/x/destroy()
var/y = /obj/z/Destroy()
/obj/allowed/Destroy() // ALLOW(lifecycle): destroy overrides take no annotation at all
// ALLOW(lifecycle): destroy overrides take no annotation at all
/obj/above/Destroy()
/datum/Destroy_extra()
/area/Destroy(
/turf/open/Destroy(force)
	qdel(M)
