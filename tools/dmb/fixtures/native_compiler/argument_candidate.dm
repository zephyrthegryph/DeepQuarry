/proc/validate_candidate(atom/A)
    return list(A)
/proc/self_source(atom/atom_target as obj|mob|turf in validate_candidate(atom_target))
    return atom_target
/proc/sibling_source(atom/first, atom/second in validate_candidate(first))
    return second
/proc/second_candidate(atom/first, atom/second in validate_candidate(second))
    return second
/datum/source_context
    var/static/list/choices = list(1)
    proc/select_value(value)
        return list(value)
    proc/proc_choice(value in select_value(__PROC__))
        return value
    proc/type_choice(value in select_value(__TYPE__))
        return value
    proc/src_choice(value in select_value(src))
        return value
    proc/static_choice(value in select_value(choices))
        return value
