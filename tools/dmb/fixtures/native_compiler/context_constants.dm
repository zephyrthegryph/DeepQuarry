/proc/global_proc_name()
    return __PROC__
/proc/global_type_name()
    return __TYPE__
/datum/context_probe/proc/member_proc_name()
    return __PROC__
/datum/context_probe/proc/member_type_name()
    return __TYPE__
/datum/context_probe/proc/call_proc_name()
    return call(src, __PROC__)()
/datum/context_probe/verb/view_source()
    set src in view(usr, 1)
    return 1
/datum/context_probe/verb/plain_view_source()
    set src in view(1)
    return 1
