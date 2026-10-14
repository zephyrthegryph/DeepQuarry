/datum/token_target
var/global/global_a = alist(1 = 2)
var/global/global_b = alist(1 = 2)
/datum/token_holder
    var/class_a = alist(1 = 2)
    var/class_b = alist(1 = 2)
/proc/static_values()
    var/static/static_a = alist(1 = 2)
    var/static/static_b = alist(1 = 2)
    return static_a
