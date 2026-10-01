/proc/named_callee(var/a,var/b)
    return a+b
/proc/named_caller()
    return named_callee(b=2, a=1)
/obj/sample
    proc/value(var/a,var/b)
        return a+b
/obj/sample/child
    value(var/a,var/b)
        return ..(b=2,a=1)
