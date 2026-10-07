/datum/token_target
/datum/token_holder
    var/const/class_const = alist(1 = 2)
    proc/read_value()
        return class_const
