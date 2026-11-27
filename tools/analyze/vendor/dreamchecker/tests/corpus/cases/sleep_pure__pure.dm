/proc/pure()
    return 1
/proc/impure()
    world << "foo"
/proc/foo()
    pure()
/proc/bar()
    impure()
/mob/proc/test()
    set SpacemanDMM_should_be_pure = TRUE
    return foo()
/mob/proc/test2()
    set SpacemanDMM_should_be_pure = TRUE
    bar()
