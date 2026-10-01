/mob
    var/value
    proc/managed()
        return list(1)
    proc/read()
        return value
    proc/change_usr(mob/other)
        usr=other
        return list(1)
/proc/usr_calls()
    usr.managed()
    return usr.read()
/proc/usr_fields()
    usr.managed()
    return usr.value
/proc/usr_assign(mob/other)
    usr.managed()
    usr=other
    return usr.read()
/proc/usr_callee_assign(mob/other)
    usr.change_usr(other)
    return usr.read()
/proc/usr_branch(flag)
    usr.managed()
    if(flag)
        return usr.read()
    return usr.value
/proc/usr_other_owner(mob/other)
    usr.managed()
    other.read()
    return usr.read()
/proc/usr_global_helper()
    usr.managed()
    usr_helper()
    return usr.read()
/proc/usr_helper()
    return list(2)
