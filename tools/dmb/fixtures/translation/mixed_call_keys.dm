/proc/mk_target(a,b)
    return a+b
/proc/mk_global(x)
    return mk_target(x,b=2)
/datum/mk_owner/proc/method(a,b)
    return a+b
/proc/mk_safe(var/datum/mk_owner/a,x)
    return a?.method(x,b=2)
/proc/mk_normal(var/datum/mk_owner/a,x)
    return a.method(x,b=2)