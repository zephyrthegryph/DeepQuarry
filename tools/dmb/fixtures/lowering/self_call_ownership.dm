/world
/datum/ownership
    proc/result(a=1,b=2)
        return list(a,b)
    proc/discard()
        result()
    proc/named()
        result(b=3,a=4)
    proc/with_args(list/L)
        result(arglist(L))
    proc/value()
        return result()
    proc/choice(a)
        (a ? 1 : result())
        return 1
    proc/reverse(a)
        (a ? result() : 1)
        return 1
    proc/multiline()
        result(
            1,
            2
        )
        return 1
