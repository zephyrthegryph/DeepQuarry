/datum/redefinition_probe
    var/last_ref
/datum/redefinition_probe/proc/foo()
    last_ref = __PROC__
    return 10
/datum/redefinition_probe/proc/foo()
    last_ref = __PROC__
    return ..() + 20
/datum/redefinition_probe/proc/foo()
    last_ref = __PROC__
    return ..() + 30
/datum/redefinition_probe/proc/under_score()
    set name = "Custom Visible Name"
    return __PROC__
/datum/redefinition_probe/proc/under_score()
    set name = "Later Visible Name"
    return ..()
/proc/redefined_global()
    return __PROC__
/proc/redefined_global()
    return __PROC__
