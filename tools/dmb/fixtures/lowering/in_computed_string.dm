/proc/in_computed_string(var/list/L,var/x)
    var/name = "[x]"
    if(name in L)
        return 1
    return 0