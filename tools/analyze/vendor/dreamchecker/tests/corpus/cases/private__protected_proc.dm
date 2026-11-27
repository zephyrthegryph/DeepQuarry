/mob/proc/protected()
    set SpacemanDMM_protected_proc = TRUE
/mob/proc/protected2()
    set SpacemanDMM_protected_proc = TRUE
/mob/subtype/protected()
    return
/mob/proc/test()
    protected()
    src.protected()
/mob/subtype/proc/test2()
    protected2()
    src.protected2()
/obj/proc/test()
    var/mob/M = new
    M.protected2()
    var/mob/subtype/S = new
    S.protected()
