#undef NORTH
#undef TRUE
/datum/shadow_left
    var/static/NORTH = 0
    proc/bump()
        NORTH++
        return NORTH
/datum/shadow_right
    var/static/NORTH = 0
    proc/bump()
        NORTH++
        return NORTH
/datum/shadow_const
    var/static/const/NORTH = 1
    proc/read()
        return NORTH
/proc/shadow_static_left()
    var/static/NORTH = 0
    NORTH++
    return NORTH
/proc/shadow_static_right()
    var/static/NORTH = 0
    NORTH++
    return NORTH
/proc/shadow_true()
    var/static/TRUE = 2
    TRUE++
    return TRUE
/proc/shadow_default_equal()
    var/static/NORTH = 1
    NORTH++
    return NORTH
/proc/shadow_call_pair()
    return list(shadow_static_left(), shadow_static_right(), shadow_default_equal())
