/var/datum/holder/OWNER
/datum/holder
    var/datum/holder/child
    var/value
    proc/replace_child(datum/holder/other)
        OWNER.child=other
        return 1
    proc/replace_root(datum/holder/other)
        OWNER=other
        return 1
    proc/read(arg)
        return value
/proc/derived_field_binding(datum/holder/other)
    return OWNER.child.replace_child(other)+OWNER.child.read()
/proc/derived_argument_binding(datum/holder/owner,datum/holder/other)
    return owner.child.replace_child(other)+owner.child.read()
/proc/derived_binding_statements(datum/holder/other)
    OWNER.child.replace_child(other)
    return OWNER.child.read()
/proc/derived_read(datum/holder/other)
    OWNER.child.replace_child(other)
    return OWNER.child.value
/proc/derived_write(datum/holder/other)
    OWNER.child.replace_child(other)
    OWNER.child.value=9
/proc/derived_compound(datum/holder/other)
    OWNER.child.replace_child(other)
    OWNER.child.value+=9
/proc/derived_index(datum/holder/other)
    OWNER.child.replace_child(other)
    return OWNER.child.vars["value"]
/proc/derived_root_replaced(datum/holder/other)
    OWNER.child.replace_root(other)
    return OWNER.child.read()
/proc/explicit_child_write(datum/holder/other)
    OWNER.child.read()
    OWNER.child=other
    return OWNER.child.read()
/proc/explicit_root_write(datum/holder/other)
    OWNER.child.read()
    OWNER=other
    return OWNER.child.read()
/proc/explicit_argument_write(datum/holder/owner,datum/holder/other)
    owner.child.read()
    owner=other
    return owner.child.read()
/proc/deep_child(datum/holder/other)
    OWNER.child.child.replace_child(other)
    return OWNER.child.child.read()
/proc/derived_nested_argument(datum/holder/other)
    return OWNER.child.read(OWNER.child.replace_child(other))
/proc/derived_other_argument(datum/holder/other)
    return OWNER.child.read(other.child.read())
/proc/derived_branch(datum/holder/other,flag)
    if(flag)
        OWNER.child.replace_child(other)
        return OWNER.child.read()
    return 0
/proc/derived_join(datum/holder/other,flag)
    if(flag)
        OWNER.child.replace_child(other)
    else
        OWNER.child.read()
    return OWNER.child.read()
/proc/derived_computed()
    return (new /datum/holder()).child.read()
/proc/derived_computed_twice()
    (new /datum/holder()).child.read()
    return (new /datum/holder()).child.read()
/datum/holder/New()
    OWNER=src
/proc/rebind_child(datum/holder/other)
    OWNER.child=other
    return 1
/proc/computed_argument_mutates_child(datum/holder/other)
    return (new /datum/holder()).child.read(rebind_child(other))

/proc/get_parent()
    return OWNER
/proc/computed_safe_child(datum/holder/other)
    return get_parent().child?.read(rebind_child(other))
/proc/computed_safe_parent(datum/holder/other)
    return get_parent()?.child.read(rebind_child(other))
/proc/computed_factory(datum/holder/other)
    return get_parent().child.read(rebind_child(other))

/proc/computed_safe_parent_nested(datum/holder/other)
    return get_parent()?.child.read(other.read(rebind_child(other)))
/proc/computed_safe_parent_index()
    return get_parent()?.child.read()?[1]
/proc/computed_safe_parent_index_arg(datum/holder/other)
    return get_parent()?.child.read(rebind_child(other))?[1]

/proc/computed_safe_parent_index_nested(datum/holder/other)
    return get_parent()?.child.read(other.read(rebind_child(other)))?[1]
