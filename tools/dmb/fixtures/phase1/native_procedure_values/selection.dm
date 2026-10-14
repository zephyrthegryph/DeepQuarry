/proc/global_callback()
    return 1
/datum/base/proc/callback()
    return 1
/datum/base/callback()
    return 2
/datum/base/verb/action()
    return 3
/datum/base
    var/global_ref = /proc/global_callback
    var/proc_ref = /datum/base/proc/callback
    var/implicit_ref = /datum/base/callback
    var/verb_ref = /datum/base/verb/action
/datum/child
    parent_type = /datum/base
    var/inherited_ref = /datum/base/proc/callback
