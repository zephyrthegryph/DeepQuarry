/proc/sleepingproc()
    sleep(1)
    input()
/proc/waitforproc()
    set waitfor = 0
    sleep(1)
    input()
    sleepingproc()
/proc/foo()
    sleepingproc()
/proc/bar()
    waitforproc()
/mob/proc/test2()
    set SpacemanDMM_should_not_sleep = TRUE
    waitforproc()
/mob/proc/test3()
    set SpacemanDMM_should_not_sleep = TRUE
    foo()
/mob/proc/test4()
    set SpacemanDMM_should_not_sleep = TRUE
    bar()
/proc/spawnthensleepproc()
    spawn(1)
        sleep(1)
/mob/proc/test5()
    set SpacemanDMM_should_not_sleep = TRUE
    spawn(1)
        sleepingproc()
/mob/proc/test6()
    set SpacemanDMM_should_not_sleep = TRUE
    spawnthensleepproc()
