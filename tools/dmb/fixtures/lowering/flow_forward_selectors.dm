/var/list/force_516 = alist()
/datum/forward_base
/datum/forward_child
    parent_type = /datum/forward_base
/proc/forward_typed(datum/forward_base/a)
    return a.action(3)
/proc/forward_safe(datum/forward_base/a)
    return a?.action(3)
/proc/forward_dynamic(a)
    return a:action(3)
/proc/forward_typed_dynamic(datum/forward_base/a)
    return a:action(3)
/proc/forward_arglist(datum/forward_base/a, list/values)
    return a.action(arglist(values))
/proc/forward_computed(datum/forward_base/a, datum/forward_base/b)
    return (a || b).action(3)
/datum/forward_base/proc/action(value = 0)
    set name = "Base Action"
    return value
/datum/forward_child/action(value = 0)
    return value + 1
/datum/unrelated_forward/proc/action(value = 0)
    set name = "Unrelated Action"
    return value + 2
/proc/backward_typed(datum/forward_base/a)
    return a.action(3)
/proc/backward_safe(datum/forward_base/a)
    return a?.action(3)
/proc/backward_dynamic(a)
    return a:action(3)
/proc/backward_typed_dynamic(datum/forward_base/a)
    return a:action(3)
/proc/backward_arglist(datum/forward_base/a, list/values)
    return a.action(arglist(values))
/proc/backward_computed(datum/forward_base/a, datum/forward_base/b)
    return (a || b).action(3)
/datum/forward_holder
    var/datum/forward_base/holder
/proc/typed_field_arg(datum/forward_base/a, datum/forward_holder/h)
    return a.action(h.holder)
/proc/safe_field_arg(datum/forward_base/a, datum/forward_holder/h)
    return a?.action(h.holder)
/proc/nested_field_arg(datum/forward_holder/a, datum/forward_holder/h)
    return a.holder?.action(h.holder)
/proc/computed_field_arg(datum/forward_base/a, datum/forward_base/b, datum/forward_holder/h)
    return (a || b).action(h.holder)