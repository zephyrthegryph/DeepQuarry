/proc/assign(const/value)
    value = 3
/proc/compound(const/value)
    value += 3
/proc/increment(const/value)
    value++
/proc/decrement(const/value)
    --value
/proc/rebind_iter(const/value)
    for(value in list(1))
        return
/proc/rebind_range(const/value)
    for(value = 1 to 3)
        return
