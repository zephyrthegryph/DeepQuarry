/proc/direct()
    return callee
/proc/caller_direct()
    return callee.caller
/proc/caller_safe()
    return callee?.caller
/proc/shadowed(callee/C)
    return C?.caller
/proc/builtin_caller()
    return caller
/proc/parameter_shadow(datum/callee)
    return callee
/proc/caller_chain()
    return callee?.caller?.caller?.proc
