/proc/increment_key(var/key)
    return key

/proc/increment_call(var/list/values, var/key)
    return values[increment_key(key)]++

/proc/increment_conditional_key(var/list/values, var/key)
    return values[key || "none"]++

/proc/increment_conditional_list(var/list/left, var/list/right, var/flag, var/key)
    return (flag ? left : right)[key]++
