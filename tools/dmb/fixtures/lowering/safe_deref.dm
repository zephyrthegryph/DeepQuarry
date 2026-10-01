/proc/safe_name(atom/A)
    return A?.name
/proc/safe_loc(atom/A)
    return A?.loc?.name

/proc/safe_stmt(atom/A)
    A?.name
    return 1

