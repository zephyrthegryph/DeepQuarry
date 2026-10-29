/datum/record
    var/value
    proc/rebuild()
        return
    proc/get_value()
        return value
    proc/set_value(next)
        value = next
/datum/record/child
    rebuild()
        return
/datum/recording
    proc/not_a_record()
        return
/datum/not_lexical
    parent_type = /datum/record
    proc/not_a_lexical_record()
        return
/datum/record/detached
    parent_type = /datum
    proc/still_a_lexical_record()
        return
