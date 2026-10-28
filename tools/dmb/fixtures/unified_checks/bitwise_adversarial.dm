/datum/holder
    var/field

/proc/postorder(a, b, c)
    return !a & (!b | c)

/proc/if_origin(a, b)
    if(!a & b)
        return 1
    return 0

/proc/do_origin(a, b)
    do
        a = a + 1
    while(!a ^ b)

/proc/ignored_setting()
    set desc = !1 & 2
    return 0

/proc/ignored_prefab()
    var/value = /datum/holder{field = !1 & 2}
    return value
