/proc/equality_result(a, b)
    return a == b
/proc/inequality_result(a, b)
    return a != b
/proc/equality_condition(a, b)
    if(a == b)
        return a
    return b
/proc/inequality_condition(a, b)
    if(a != b)
        return a
    return b
/proc/equality_and(a, b, c)
    return (a == b) && c
/proc/equality_or(a, b, c)
    return (a == b) || c
/proc/equality_not(a, b)
    return !(a == b)
/proc/equality_sum(a, b, c)
    return (a == b) + c
/proc/equality_list(a, b)
    return list(a == b)
/proc/equivalent_result(a, b)
    return a ~= b
/proc/not_equivalent_result(a, b)
    return a ~! b
/proc/condition_eq_or(a, b, c, d)
    if((a == b) || (c == d))
        return a
    return b
/proc/condition_eq_and(a, b, c, d)
    if((a == b) && (c == d))
        return a
    return b
/proc/condition_type_or(a, b, c)
    if(istype(a, b) || (b == c))
        return a
    return b
/proc/condition_type_and(a, b, c)
    if(istype(a, b) && (b == c))
        return a
    return b
/proc/condition_nested(a, b, c, d)
    if((a || (b == c)) && (c == d))
        return a
    return b
/proc/condition_membership_or(a, b, list/items)
    if(a || (b in items))
        return a
    return b
/proc/condition_membership_and(a, b, list/items)
    if(a && (b in items))
        return a
    return b
