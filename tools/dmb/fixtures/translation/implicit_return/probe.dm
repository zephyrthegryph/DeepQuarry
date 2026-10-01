/proc/probe_dot(a)
    . = a
/proc/probe_dot_add(a)
    . = a
    . += 1
/proc/probe_noreturn(a)
    var/x = a
/proc/probe_return_name(a)
    var/return_value = a
    return_value += 1
