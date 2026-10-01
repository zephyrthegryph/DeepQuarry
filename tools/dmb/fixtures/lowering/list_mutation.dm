/proc/list_ops(list/L,x)
    L += x
    L -= x
    return L
/proc/index_set(list/L,k,v)
    L[k] = v
    return L[k]
