/datum/token_target
/datum/token_holder
    var/const/class_const = typesof(/datum/token_target)
    proc/read_value()
        return class_const
