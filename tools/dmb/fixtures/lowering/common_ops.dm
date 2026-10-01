/proc/member(x, L)
    return x in L
/proc/emit(x, y)
    x << y
/proc/getstep(a,b)
    return get_step(a,b)
/proc/choose3(a,b,c)
    return pick(a,b,c)
/proc/inittype(atom/x)
    return initial(x.name)
