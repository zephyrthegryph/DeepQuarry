/var/list/force_516 = alist()
/datum/call_base
    var/name = "Display Name"
/datum/call_base/proc/action()
    set name = "Action Display"
    return 1
/datum/call_child
    parent_type = /datum/call_base
/datum/call_child/action()
    return 2
/datum/call_other/proc/action()
    return 3
/datum/call_final/proc/action()
    set name = "Final Action Display"
    return 4
/proc/final_call(datum/call_final/a)
    return a.action()
/proc/final_safe_call(datum/call_final/a)
    return a?.action()
/mob/var/mode = 0
/mob/proc/mob_action(value)
    return 5
/proc/usr_call()
    return usr.mob_action(!usr.mode)
/proc/typed_mob_call(mob/a)
    return a.mob_action()
/proc/typed_call(datum/call_base/a)
    return a.action()
/proc/child_call(datum/call_child/a)
    return a.action()
/proc/dynamic_call(a)
    return a:action()
/proc/typed_dynamic_call(datum/call_base/a)
    return a:action()
/proc/typed_safe_call(datum/call_base/a)
    return a?.action()
/proc/typed_computed_call(datum/call_base/a)
    return (a || new /datum/call_base).action()
