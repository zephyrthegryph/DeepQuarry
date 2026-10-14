/datum/base
    var/a = 0
    var/b = 0
/datum/probe
    var/one = /datum/base {a=1;b=2}
    var/two = /datum/base {b=2;a=1}
/proc/one()
    return (/datum/base {a=1;b=2})
/proc/two()
    return (/datum/base {b=2;a=1})