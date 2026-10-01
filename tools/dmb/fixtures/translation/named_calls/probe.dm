/proc/f(a,b,c)
    return a+b+c
/proc/named()
    return f(c=3,a=1,b=2)
/datum/x
    New(a,b,c)
        ..()
    proc/f(a,b,c)
        return a+b+c
/proc/member(datum/x/x)
    return x.f(c=3,a=1,b=2)
/proc/newthing()
    return new /datum/x(c=3,a=1,b=2)
