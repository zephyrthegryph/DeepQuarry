/var/const/type_datum = /datum/path_probe
/var/const/type_obj = /obj/path_probe
/var/const/type_mob = /mob/path_probe
/var/const/type_turf = /turf/path_probe
/var/const/type_area = /area/path_probe
/var/const/type_list = /list
/var/const/type_client = /client
/var/const/type_copy = type_obj
/obj/path_probe
    parent_type = /obj/path_parent
/obj/path_parent
    name = "Inherited parent"
    density = 1
/datum/path_probe
    var/const/type_field = /area/path_probe
/mob/path_probe
    see_in_dark = 7
/turf/path_probe
/area/path_probe
/proc/path_static()
    var/static/const/local_constant = 1 + 2
    return local_constant
