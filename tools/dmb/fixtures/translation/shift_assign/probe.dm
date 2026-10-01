/proc/right_shift_assign(x)
    x >>= 1
    return x
/proc/left_shift_assign(x)
    x <<= 2
    return x
/proc/right_shift_expr(x)
    return (x >>= 1)
