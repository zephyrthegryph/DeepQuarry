/mob/probe/proc/dynamic(mob/M as mob in oview(src))
    return M
/proc/frame(callee/caller)
    return caller.proc
/proc/readonly(const/value)
    return value
/proc/readonly_list(const/list/values)
    values[1] = 7
    return values
