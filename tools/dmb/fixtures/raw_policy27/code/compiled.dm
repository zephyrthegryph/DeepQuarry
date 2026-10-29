/datum/probe/proc/run(user)
    sleep(1)
    sleep(2) // ALLOW(scheduler): this is an intentional annotation fixture
    RegisterSignal(src, "event", null)
    weakref(src)
    del(src)
