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
    C.inherited().missing_inherited
    C.overridden().missing_override
    C.null_return().missing_null
