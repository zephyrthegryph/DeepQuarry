/mob/proc/test()
    set SpacemanDMM_should_call_parent = 1

/mob/subtype/test()
    set SpacemanDMM_should_call_parent = 0
    return
