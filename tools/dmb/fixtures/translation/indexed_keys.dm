/proc/indexed_lower(list/L, key, value)
    L[lowertext(key)] = value
    return L
/proc/indexed_upper(list/L, key, value)
    L[uppertext(key)] = value
    return L
