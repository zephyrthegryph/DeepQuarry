/datum/base/proc/inherited()
    return null
/datum/base/proc/overridden()
    return null
/datum/base/proc/null_return()
    return null
/datum/base/child/overridden()
    return null
/datum/base/child/null_return()
    set SpacemanDMM_return_type = null
    return null
/proc/probe(datum/base/child/C)
    C.inherited().invoke(hidden_missing())
    C.overridden().invoke(hidden_missing())
    C.null_return().invoke(hidden_missing())
