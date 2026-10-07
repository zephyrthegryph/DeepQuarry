/datum/worker_child
    parent_type = /datum/worker_base
    value = 2
    read_value()
        return value + 1

/datum/worker_base
    value = 4
