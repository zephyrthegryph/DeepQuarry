/datum/probe/proc/static_vars()
    var/static/list/vars = list("child")
    return vars
/datum/probe/proc/static_other()
    var/static/list/other = list("child")
    return other
/datum/probe/proc/local_vars()
    var/list/vars = list("local")
    return vars
/proc/builtin_vars()
    return global.vars