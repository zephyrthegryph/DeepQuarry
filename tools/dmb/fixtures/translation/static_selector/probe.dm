/var/list/force_516 = alist()
/datum/selector_static_caller/proc/test(datum/selector_static_base/B, value)
    return B.action(value)
/datum/selector_static_base/proc/action(value)
    set name = "Base Action"
    var/obj/unused = new
    if(unused)
        return value
    return value
/datum/selector_static_child
    parent_type = /datum/selector_static_base
/datum/selector_static_child/action(value)
    return value + 1
/datum/selector_static_unrelated/proc/action(value)
    set name = "Other Action"
    return value
