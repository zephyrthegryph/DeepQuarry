/proc/unary(a, b)
    return !a in b
/proc/binary(a, b, c)
    return a + b in c
/proc/assignment(a, b, c)
    return a = b in c
/proc/ternary(a, b, c, d)
    return a ? b : c in d
/proc/grouped(a, b)
    return (!a in b)
/proc/interpolated(a, b)
    return "[!a in b]"
