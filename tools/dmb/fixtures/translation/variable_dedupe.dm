/datum/a
    var/shared = 5
    var/unique = 7

/datum/b
    var/shared = 5
    var/other = 9

/datum/a/child
    shared = 7

/datum/a/child/grandchild
    var/grand = 11

/obj/fixture/defaults
    plane = 5
    glide_size = 7

/obj/fixture/defaults/child
    name = "Child"

/obj/fixture/cash
    var/access = list()
    access = 200

/mob/fixture/eyes
    sight = 4
    see_in_dark = 7
    see_invisible = 20

/mob/fixture/eyes/child
    see_invisible = 30

/area/fixture/glow
    luminosity = 5
