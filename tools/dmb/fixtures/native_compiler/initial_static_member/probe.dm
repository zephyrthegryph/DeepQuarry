/datum/base
    var/message = "base text"
/datum/base/child
    message = "child text"
/proc/read_path()
    return initial(/datum/base::message)
/proc/read_child()
    return initial(/datum/base/child::message)
/proc/read_value(datum/base/value)
    return initial(value::message)
/proc/read_side_effect()
    return initial(make_value()::message)
/proc/make_value()
    return new /datum/base
/proc/saved_path()
    return issaved(/datum/base::message)
