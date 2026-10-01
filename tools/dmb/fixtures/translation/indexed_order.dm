/proc/io_list(list/L)
    return L
/proc/io_key(key)
    return key
/proc/io_value(value)
    return value
/proc/indexed_order(list/L, key, value)
    io_list(L)[io_key(key)] = io_value(value)
    return L
