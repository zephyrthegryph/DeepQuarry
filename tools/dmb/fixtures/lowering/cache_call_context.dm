/world
/datum/cache_call_context
    var/value=1
    var/datum/cache_call_context/child
    proc/change_src()
        src=null
    proc/context_method()
        var/a=value
        change_src()
        return value+a
    proc/context_global()
        var/a=value
        cache_context_helper()
        return value+a
    proc/chained_global()
        var/a=child.value
        cache_context_child(src)
        return child.value+a
    proc/world_global()
        var/a=world.time
        cache_context_helper()
        return world.time+a
/proc/cache_context_helper()
    src=null
/proc/cache_context_child(datum/cache_call_context/o)
    o.child=null
/datum/cache_call_context/proc/context_new()
    var/a=value
    var/datum/cache_call_context/o=new
    return value+a+isnull(o)
/datum/cache_call_context/proc/context_new_arglist()
    var/a=value
    var/list/L=list()
    var/datum/cache_call_context/o=new /datum/cache_call_context(arglist(L))
    return value+a+isnull(o)
/datum/cache_call_context/proc/context_arg(datum/cache_call_context/o)
    var/a=o.value
    cache_context_helper()
    return o.value+a
/datum/cache_call_context/proc/context_args_alias(datum/cache_call_context/o)
    var/a=o.value
    cache_context_args(args)
    return o.value+a
/datum/cache_call_context/proc/context_local()
    var/datum/cache_call_context/B=child
    var/a=B.value
    cache_context_helper()
    return B.value+a
/proc/cache_context_args(list/L)
    L[1]=new /datum/cache_call_context
/datum/cache_call_context/proc/context_list_set()
    var/datum/cache_call_context/B=child
    var/a=B.value
    var/list/L=list()
    L["x"]=1
    return B.value+a
