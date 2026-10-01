/datum/proc/foo(var/x)
    return x + 1
/proc/dynamic_call_test(var/datum/D)
    return call(D, "foo")(4)
