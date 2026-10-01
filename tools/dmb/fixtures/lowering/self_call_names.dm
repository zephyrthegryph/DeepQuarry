/datum/self_base/proc/record_cost()
    set name = "record cost alias"
    return 1
/datum/self_base/proc/plain_name()
    return 2
/datum/self_base/proc/call_alias()
    return record_cost()
/datum/self_base/proc/call_plain()
    return plain_name()
/datum/self_child
    parent_type = /datum/self_base
/datum/self_child/proc/call_inherited()
    return record_cost()
/datum/self_child/record_cost()
    return 3
/datum/self_child/proc/call_override()
    return record_cost()
/datum/self_sibling
    parent_type = /datum/self_base
/datum/self_sibling/proc/call_inherited()
    return record_cost()
/datum/self_other/proc/record_cost()
    set name = "unrelated cost"
    return 4
