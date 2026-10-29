/proc/prefix()
    set SpacemanDMM_should_be_pure = 1
    return 1

/proc/late(a)
    a = 1
    set SpacemanDMM_should_be_pure = 0
    set background = 1

/proc/nested(a)
    if(a)
        set SpacemanDMM_should_be_pure = 1
    a = 2

/proc/unreachable()
    return
    set SpacemanDMM_should_be_pure = 1
