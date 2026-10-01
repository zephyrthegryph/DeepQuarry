/proc/foo(x)
    return x
/proc/probe_call()
    return global.foo(3)
/proc/probe_vars()
    return global.vars
