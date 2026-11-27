/datum/proc/checker()
        set SpacemanDMM_should_not_sleep = 1

/datum/proc/proxy()
        sleeper()

/datum/sub/checker()
        proxy()

/proc/sleeper()
        sleep(1)

/datum/hijack/proxy()
        sleep(1)
