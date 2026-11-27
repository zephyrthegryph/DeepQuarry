/mob
    var/SpacemanDMM_private/foo = TRUE
    var/SpacemanDMM_private/bar = TRUE
/mob/subtype
    foo = FALSE
/mob/proc/test()
    foo = FALSE
/mob/subtype/proc/test2()
    bar = FALSE
/obj/proc/test()
    var/mob/M = new
    M.bar = TRUE
    var/mob/subtype/S = new
    S.foo = TRUE
