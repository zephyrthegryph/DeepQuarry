/datum/safe_index_key
    var/value="x"
/proc/safe_computed_index(list/a,datum/safe_index_key/key)
    return a?[key.value]
/proc/safe_nested_index(list/a,b,c)
    return a?[b]?[c]

/proc/safe_index_assign(list/a,b,c)
    a?[b] = c
/proc/safe_index_add(list/a,b,c)
    a?[b] += c
