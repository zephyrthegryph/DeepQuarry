/datum/branch_holder
    var/datum/branch_holder/child
    var/value
    proc/read(arg)
        return value
/proc/index_sub(list/subscribers,type,thing)
    if(!thing||!subscribers[type])
        return
    subscribers[type]-=thing
    return subscribers[type]
/proc/index_add(list/subscribers,type,thing)
    if(!thing||!subscribers[type])
        return
    subscribers[type]+=thing
    return subscribers[type]
/proc/index_sub_expression(list/subscribers,type,thing)
    if(!thing||!subscribers[type])
        return
    return (subscribers[type]-=thing)
/proc/safe_and(flag,datum/branch_holder/O)
    if(flag&&O?.child?.read())
        return 1
    return 0
/proc/safe_or(flag,datum/branch_holder/O)
    if(flag||O?.child?.read())
        return 1
    return 0
/proc/safe_and_argument(flag,datum/branch_holder/O,datum/branch_holder/A)
    return O.read(flag&&A?.child?.read())
/proc/safe_nested_logic(flag,datum/branch_holder/A,datum/branch_holder/B)
    if(flag&&(A?.child?.read()||B?.child?.read()))
        return 1
    return 0
/proc/safe_ternary(flag,datum/branch_holder/O)
    return flag?1:O?.child?.read()
