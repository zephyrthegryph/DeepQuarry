/datum/record
    proc/read()
        return
/datum/record/child
/datum/record/other
    read()
        return
/datum/record/detached
    parent_type = /datum
    proc/detached()
        return
/datum/elsewhere
    parent_type = /datum/record
    proc/not_lexically_record()
        return
