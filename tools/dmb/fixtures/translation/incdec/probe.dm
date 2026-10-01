/proc/post_statement()
    var/x = 1
    x++
    return x
/proc/pre_statement()
    var/x = 1
    ++x
    return x
/proc/post_expr()
    var/x = 1
    return x++
/proc/pre_expr()
    var/x = 1
    return ++x
/proc/post_index(list/x, i)
    x[i]++
    return x[i]
