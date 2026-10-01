/proc/index_append(var/list/L,var/i,var/v)
    L[i] += v
/proc/index_append_lookup(var/list/L,var/i,var/list/other)
    L[i] += other[i]
/proc/index_append_computed_key(var/list/L,var/i,var/list/other)
    L[(i % 2) + 1] += other[i]
