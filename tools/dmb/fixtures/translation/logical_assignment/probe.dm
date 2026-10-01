/datum/x
    var/value
/proc/or_assign(x,y)
    x ||= y
    return x
/proc/and_assign(x,y)
    x &&= y
    return x
/proc/member(datum/x/x)
    x.value ||= 3
    return x.value
