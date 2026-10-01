/proc/ia_append(L, k, flag, A)
    L[k] += flag ? A : list()
/proc/ia_subtract(L, k, flag, A)
    L[k] -= flag ? A : 1
/proc/ia_multiply(L, k, flag, A)
    L[k] *= flag ? A : 1
