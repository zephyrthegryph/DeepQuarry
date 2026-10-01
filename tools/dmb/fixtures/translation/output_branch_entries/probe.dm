var/G
/proc/mark(v)
    return v
    return 0
/proc/world_else(flag)
    if(flag)
        return 1
    else
        world << "else"
    return 0
/proc/world_early(flag)
    if(flag)
        return 1
    world << "early"
    return 0
/proc/arg_else(flag,D)
    if(flag)
        return 1
    else
        D << "arg"
    return 0
/proc/global_early(flag)
    if(flag)
        return 1
    G << "global"
    return 0
/proc/usr_else(flag)
    if(flag)
        return 1
    else
        usr << "usr"
    return 0
/datum/holder
    var/target
/datum/holder/proc/src_else(flag)
    if(flag)
        return 1
    else
        src << "src"
    return 0
/proc/local_early(flag,D)
    var/L=D
    if(flag)
        return 1
    L << "local"
    return 0
/proc/formatted(flag,v)
    if(flag)
        return 1
    world << "value:[v]"
    return 0
/proc/conditional(flag,v)
    if(flag)
        return 1
    world << (v ? mark("yes") : mark("no"))
    return 0
/proc/backward_label(flag)
    label:
    world << "label"
    if(flag)
        flag=0
        goto label
    return 0
/proc/field_early(flag,datum/holder/H)
    if(flag)
        return 1
    H.target << "field"
    return 0
/proc/indexed_early(flag,list/L,key)
    if(flag)
        return 1
    L[key] << "indexed"
    return 0
