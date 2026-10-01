/obj/sample
    proc/helper(var/x)
        return x+1
    proc/caller(var/x)
        return helper(x)
    proc/caller_named()
        return helper(x=3)
    proc/caller_arglist(var/list/L)
        return helper(arglist(L))
