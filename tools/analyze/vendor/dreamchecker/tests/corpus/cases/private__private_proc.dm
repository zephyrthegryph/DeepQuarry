/mob/proc/private()
    set SpacemanDMM_private_proc = TRUE
/mob/proc/private2()
    set SpacemanDMM_private_proc = TRUE
/mob/subtype/private()
    return
/mob/proc/test()
    private2()
    src.private2()
/mob/subtype/proc/test2()
    private2()
    src.private2()
/obj/proc/test()
    var/mob/M = new
    M.private2()
    var/mob/subtype/S = new
    S.private()
