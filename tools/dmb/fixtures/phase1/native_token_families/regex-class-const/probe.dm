/datum/token_target
/datum/token_holder
    var/const/class_const = regex("a")
    proc/read_value()
        return class_const
