/datum/token_target
var/global/global_a = typesof(/datum/token_target)
var/global/global_b = typesof(/datum/token_target)
/datum/token_holder
    var/class_a = typesof(/datum/token_target)
    var/class_b = typesof(/datum/token_target)
/proc/static_values()
    var/static/static_a = typesof(/datum/token_target)
    var/static/static_b = typesof(/datum/token_target)
    return static_a
