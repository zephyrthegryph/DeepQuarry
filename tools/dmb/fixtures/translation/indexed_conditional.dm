/proc/ic_round(var/list/out, var/list/B, x, y, sum)
    out[x] = round(sum + (y == 5 ? B[x+16] : 0), 0.001)
/proc/ic_nested(var/list/out, k, a, b, c)
    out[k] = 4 + (a ? (b ? 2 : 3) : c) * 2
/proc/ic_value(a)
    return a
/proc/ic_effect(var/list/out, k, a)
    out[k] = ic_value(a ? ic_value(2) : ic_value(3)) + ic_value(4)
/proc/ic_two(var/list/out, k, a, b)
    out[k] = (a ? 2 : 3) + (b ? 4 : 5)