/procpath
    var/name as text
    var/desc as text
    var/category as text
    var/invisibility as num
    var/hidden as num
/datum/holder
    var/procpath/comparison = /proc/compare
/proc/compare(a,b)
    return a-b
/proc/read(procpath/value)
    return value.name
/proc/type_value()
    return /procpath

/standalone
    var/value
/proc/standalone_type()
    return /standalone


/appearance
    var/value
/hook/startup
    var/value
/proc/appearance_type()
    return /appearance
/proc/hook_type()
    return /hook

