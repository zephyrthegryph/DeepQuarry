/proc/in_or(a,b,c)
    return a in b || c
/proc/in_or_explicit(a,b,c)
    return (a in b) || c
/proc/in_ternary(a,b)
    return a in list(1,2) ? 3 : 4
/proc/in_ternary_explicit(a,b)
    return (a in list(1,2)) ? 3 : 4