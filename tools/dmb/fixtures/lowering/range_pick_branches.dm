/world
/proc/range_cond(x,a,b)
    return x in (a ? 1 : 2) to (b ? 3 : 4)
/proc/range_short(x,a,b)
    return x in (a || 1) to (b && 4)
/proc/pick_cond(a,b)
    return pick((a ? 1 : 2); (b ? 3 : 4), 1; (a || 5))
/proc/pick_value(a,b)
    return pick(1; (a ? 1 : 2), 2; (b || 5))
