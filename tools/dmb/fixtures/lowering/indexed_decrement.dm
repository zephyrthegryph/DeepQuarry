/proc/indexed_decrement(var/list/values, var/key)
    return values[key]--

/proc/indexed_decrement_statement(var/list/values, var/key)
    values[key]--

/proc/indexed_float_clear(var/list/values, var/key)
    values[key] = 0
