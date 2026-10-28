/proc/grouped(a, b)
    return (!a & b)
/proc/interpolated(a, b)
    return "[!a & b]"
/proc/call_argument(a, b)
    return grouped(!a & b, b)
