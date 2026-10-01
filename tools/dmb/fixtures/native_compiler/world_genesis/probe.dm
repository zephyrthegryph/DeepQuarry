var/global/marker = 0
var/global/later = set_later()
/proc/set_later()
    marker = marker * 10 + 2
    return marker
/proc/set_class()
    return 3
/proc/set_proc()
    return 4
/datum/static_holder
    var/static/class_value = set_class()
/proc/earlier_proc()
    var/static/proc_value = set_proc()
    return proc_value
/world/proc/Genesis()
    marker = marker * 10 + 1
/world/proc/_()
    var/static/_ = world.Genesis()
/world/New()
    return
