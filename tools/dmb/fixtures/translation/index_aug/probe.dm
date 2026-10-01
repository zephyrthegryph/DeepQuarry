/proc/index_aug(list/L, i, x)
    L[i] += x
    return L[i]
/proc/index_aug_expr(list/L, i, x)
    return (L[i] += x)
