/datum/attachment
/datum/message
    var/datum/attachment/attachment
/datum/other_message
    var/datum/message/attachment
/datum/api
    var/datum/message/value
/datum/api/proc/current() as /datum/message
    return value
/datum/api/proc/check()
    return istype(current().attachment)
/datum/api/child/current()
    return ..()
/datum/api/child/proc/check_child()
    return istype(current().attachment)
/datum/api/child/grandchild/current()
    return ..()
/datum/api/child/grandchild/proc/check_grandchild()
    return istype(current().attachment)
/proc/get_message() as /datum/message
    return new /datum/message
/proc/get_anything() as anything
    return null
/proc/check_global()
    return istype(get_message().attachment)
/proc/check_member(datum/api/target)
    return istype(target.current().attachment)
/proc/check_safe_member(datum/api/target)
    return istype(target?.current().attachment)
