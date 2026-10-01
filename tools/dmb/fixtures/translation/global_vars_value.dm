var/global/probe = 5
/proc/global_vars_read()
    return global.vars
/proc/global_vars_index()
    return global.vars["probe"]
/proc/global_vars_write()
    global.vars["probe"] = 7
    return probe
/proc/global_vars_alias()
    var/list/alias = global.vars
    return alias
/proc/global_vars_enumerate()
    for(var/name in global.vars)
        return name
