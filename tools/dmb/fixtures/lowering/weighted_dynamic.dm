/proc/weighted_dynamic(var/w)
    return pick(10;"a", w;"b")
/proc/weighted_dynamic_three(var/w)
    return pick(10;"a", w;"b", 20;"c")
