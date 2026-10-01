/datum/ms_owner/proc/f(value)
    return value
/datum/ms_owner/proc/g()
    return 7
/proc/ms_outer_safe(var/datum/ms_owner/a,var/datum/ms_owner/b)
    return a?.f(b.g())
/proc/ms_inner_safe(var/datum/ms_owner/a,var/datum/ms_owner/b)
    return a.f(b?.g())
/proc/ms_both_safe(var/datum/ms_owner/a,var/datum/ms_owner/b)
    return a?.f(b?.g())