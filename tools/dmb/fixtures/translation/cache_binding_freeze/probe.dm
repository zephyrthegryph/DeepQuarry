/var/datum/cache_binding/OWNER
/datum/cache_binding
    var/value
    proc/replace_owner(datum/cache_binding/other)
        OWNER=other
        return 1
    proc/replace_binding(list/L,datum/cache_binding/other)
        L[1]=other
        return 1
    proc/read(arg)
        return value
    proc/src_calls()
        return read()+read()
/proc/global_binding(datum/cache_binding/other)
    return OWNER.replace_owner(other)+OWNER.read()
/proc/argument_binding(datum/cache_binding/owner,datum/cache_binding/other)
    return owner.replace_binding(args,other)+owner.read()
/proc/global_binding_statements(datum/cache_binding/other)
    OWNER.replace_owner(other)
    return OWNER.read()
/proc/global_explicit_rebind(datum/cache_binding/other)
    OWNER.read()
    OWNER=other
    return OWNER.read()
/proc/argument_explicit_rebind(datum/cache_binding/owner,datum/cache_binding/other)
    owner.read()
    owner=other
    return owner.read()
/proc/local_binding(datum/cache_binding/other)
    var/datum/cache_binding/local=OWNER
    return local.replace_owner(other)+local.read()
/proc/local_explicit_rebind(datum/cache_binding/other)
    var/datum/cache_binding/local=OWNER
    local.read()
    local=other
    return local.read()
/proc/field_mutation()
    OWNER.read()
    OWNER.value=7
    return OWNER.read()
/proc/nested_argument(datum/cache_binding/other)
    return OWNER.read(OWNER.replace_owner(other))
/proc/branch_owner(datum/cache_binding/other,flag)
    if(flag)
        OWNER.read()
    else
        other.read()
    return OWNER.read()
/proc/world_calls()
    world.Export("a")
    return world.Export("b")
/proc/field_read(datum/cache_binding/other)
    OWNER.replace_owner(other)
    return OWNER.value
/proc/field_write(datum/cache_binding/other)
    OWNER.replace_owner(other)
    OWNER.value=9
/proc/field_compound(datum/cache_binding/other)
    OWNER.replace_owner(other)
    OWNER.value+=9
/proc/index_access(datum/cache_binding/other)
    OWNER.replace_owner(other)
    return OWNER.vars["value"]
/proc/branch_same_owner(datum/cache_binding/other,flag)
    if(flag)
        OWNER.replace_owner(other)
    else
        OWNER.read()
    return OWNER.read()
/proc/global_nested_other(datum/cache_binding/other)
    return OWNER.read(other.read())
/proc/argument_index_rebind(datum/cache_binding/owner,datum/cache_binding/other)
    owner.read()
    args[1]=other
    return owner.read()
/proc/global_index_rebind(datum/cache_binding/other)
    OWNER.read()
    global.vars["OWNER"]=other
    return OWNER.read()
/proc/local_unrelated_write(datum/cache_binding/other)
    OWNER.read()
    var/x=1
    return OWNER.read(x)
/proc/replace_global(datum/cache_binding/other)
    OWNER=other
    return 1
/proc/unrelated_helper()
    return 1
/proc/global_helper_replace(datum/cache_binding/other)
    OWNER.read()
    replace_global(other)
    return OWNER.read()
/proc/global_helper_unrelated()
    OWNER.read()
    unrelated_helper()
    return OWNER.read()
/datum/cache_binding/proc/self_boundary(flag)
    if(flag) return 1
    OWNER.read()
    .(1)
    return OWNER.read()
/datum/cache_binding/proc/parent_boundary()
    return 1
/datum/cache_binding/sub/parent_boundary()
    OWNER.read()
    ..()
    return OWNER.read()
/datum/cache_binding/sub/New(datum/cache_binding/other)
    OWNER=other
/proc/new_boundary(datum/cache_binding/other)
    OWNER.read()
    new /datum/cache_binding/sub(other)
    return OWNER.read()

/proc/branch_replacement(datum/cache_binding/other,flag)
    if(flag)
        OWNER.replace_owner(other)
        return OWNER.read()
    return 0
/proc/branch_before_after(datum/cache_binding/other,flag)
    OWNER.read()
    if(flag)
        OWNER.replace_owner(other)
        OWNER.read()
    return OWNER.read()

/proc/switch_replacement(datum/cache_binding/other,flag)
    switch(flag)
        if(1)
            OWNER.replace_owner(other)
            return OWNER.read()
    return 0

/proc/branch_write(datum/cache_binding/other,flag)
    if(flag)
        OWNER.replace_owner(other)
        OWNER.value=9
    return 0

/proc/branch_existing_write(datum/cache_binding/other,flag)
    OWNER.read()
    if(flag)
        OWNER.replace_owner(other)
        OWNER.value=9
    return 0
