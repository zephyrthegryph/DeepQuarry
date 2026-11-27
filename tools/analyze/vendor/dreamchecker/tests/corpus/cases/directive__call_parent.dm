/mob/proc/test()
    set SpacemanDMM_should_call_parent = 1

/mob/subtype/test()
    return
/mob/anothertype/test()
    ..()
