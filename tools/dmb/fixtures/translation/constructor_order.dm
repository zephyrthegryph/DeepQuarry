/datum/ctor
    var/foo
/datum/ctor/New(a,b)
    ..()
/datum/holder
    var/typefield = /datum/ctor
/proc/ctor_type()
    return /datum/ctor
/proc/ctor_arg()
    return 7
/proc/n_computed(datum/holder/h)
    return new h.typefield(ctor_arg())
/proc/n_field(datum/holder/h,x)
    return new h.typefield(x+1)
/proc/n_cond_type(cond,x)
    var/path = cond ? /datum/ctor : /datum/holder
    return new path(x)
/proc/n_cond_arg(cond,x)
    return new /datum/ctor(cond ? x : 7)
/proc/n_arglist(path,list/L)
    return new path(arglist(L))
/proc/n_named(path,x)
    return new path(a=x,b=2)
/proc/n_modified(x)
    return new /datum/ctor{foo=3}(x)
/proc/n_index(list/L,x)
    var/path=L[1]
    return new path(x)
/proc/n_procverb(destination)
    return new /datum/ctor/verb/test(destination)
/datum/ctor/verb/test()
    return
