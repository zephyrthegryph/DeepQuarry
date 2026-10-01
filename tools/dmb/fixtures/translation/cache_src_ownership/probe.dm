/datum/holder
    var/value
    proc/managed()
        return list(1)
    proc/read_implicit()
        managed()
        return value
    proc/read_explicit()
        src.managed()
        return src.value
    proc/read_global()
        src.managed()
        helper()
        return src.value
/proc/helper()
    return list(2)
/datum/holder
    var/datum/holder/child
    proc/write_after()
        src.managed()
        src.value=9
        return src.value
    proc/compound_after()
        src.managed()
        src.value+=9
        return src.value
    proc/postfix_after()
        src.managed()
        src.value++
        return src.value
    proc/other_owner(datum/holder/O)
        src.managed()
        O.managed()
        return src.value
    proc/derived_owner()
        src.managed()
        src.child.managed()
        return src.value
    proc/getter_first()
        return src.value+src.value
    proc/branch_after(flag)
        src.managed()
        if(flag)
            return src.value
        return src.value
    proc/guard_after(datum/holder/O)
        src.managed()
        return O?.value || src.value
    proc/assignment_expression()
        src.managed()
        return (src.value=9)+src.value
/datum/holder/proc/change_own_src(datum/holder/O)
    src=O
    return list(1)
/datum/holder/proc/write_src(datum/holder/O)
    src.managed()
    src=O
    return src.value
/datum/holder/proc/callee_src(datum/holder/O)
    src.change_own_src(O)
    return src.value
