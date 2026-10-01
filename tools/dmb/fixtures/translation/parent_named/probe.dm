/datum/base/proc/foo(a, infix)
    return infix
/datum/base/child/foo(a, infix)
    return ..(a, infix="x")
