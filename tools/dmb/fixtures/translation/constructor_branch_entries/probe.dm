/proc/mark(v)
    return v
/datum/holder/New(v)
    return
/proc/file_entry(flag,path)
    if(!flag)
        return
    return file("[path]/test.html")
/proc/file_arglist(flag,list/L)
    if(!flag)
        return
    return file(arglist(L))
/proc/sound_entry(flag,path)
    if(!flag)
        return
    return sound(path)
/proc/sound_named(flag,path)
    if(!flag)
        return
    return sound(file=path, repeat=1)
/proc/icon_entry(flag,path)
    if(!flag)
        return
    return icon(path)
/proc/icon_named(flag,path)
    if(!flag)
        return
    return icon(icon=path, icon_state="x")
/proc/type_entry(flag,v)
    if(!flag)
        return
    return new /datum/holder(v)
/proc/file_conditional(flag,a,b)
    if(!flag)
        return
    return file(flag ? mark(a) : mark(b))
/proc/file_short(flag,a,b)
    if(!flag)
        return
    return file(a || mark(b))
/proc/type_conditional(flag,a,b)
    if(!flag)
        return
    return new /datum/holder(flag ? mark(a) : mark(b))
/proc/sound_conditional(flag,a,b)
    if(!flag)
        return
    return sound(flag ? mark(a) : mark(b))
/proc/icon_conditional(flag,a,b)
    if(!flag)
        return
    return icon(flag ? mark(a) : mark(b))
/proc/generator_entry(flag,v)
    if(!flag)
        return
    return generator("sphere",v,v)
/proc/sound_named_conditional(flag,a,b)
    if(!flag)
        return
    return sound(file=flag ? mark(a) : mark(b), repeat=1)
/proc/icon_named_conditional(flag,a,b)
    if(!flag)
        return
    return icon(icon=flag ? mark(a) : mark(b), icon_state="x")
/proc/generator_conditional(flag,a,b)
    if(!flag)
        return
    return generator("sphere",flag ? mark(a) : mark(b),a)
/proc/type_named_conditional(flag,a,b)
    if(!flag)
        return
    return new /datum/holder(v=flag ? mark(a) : mark(b))
/proc/dynamic_entry(flag,path,v)
    if(!flag)
        return
    return new path(v)
/proc/dynamic_conditional(flag,path,a,b)
    if(!flag)
        return
    return new path(flag ? mark(a) : mark(b))
