/mob/tagged
/obj/tagged
/turf/tagged
/area/tagged
/datum/tagged
/datum/type_tag_fixture
    var/tag_mob_root = /mob
    var/tag_mob_child = /mob/tagged
    var/tag_movable_root = /atom/movable
    var/tag_movable_child = /obj/tagged
    var/tag_atom_root = /atom
    var/tag_atom_child = /turf/tagged
    var/tag_area_path = /area/tagged
    var/tag_datum_path = /datum/tagged
/datum/type_tag_fixture/child
    tag_mob_root = /mob/tagged
    tag_movable_root = /atom/movable
    tag_atom_root = /atom/movable
