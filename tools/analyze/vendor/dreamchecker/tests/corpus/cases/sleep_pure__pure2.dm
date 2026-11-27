/mob/proc/test()
    set SpacemanDMM_should_be_pure = TRUE
    return 1
/mob/proc/test2()
    test()
/mob/proc/test3()
    return test()
