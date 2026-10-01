/proc/probe_args(a,b)
    return args
/proc/probe_argsindex(a,b)
    return args[2]
/proc/probe_argswrite(a,b)
    args[2] = 9
    return b
