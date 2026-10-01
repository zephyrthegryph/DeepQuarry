/world
/proc/md_short(n)
    var/list/L[n || 2][n && 4]
    return L.len
/proc/md_nested(n)
    var/list/L[n ? (n || 2) : 3][n && (n ? 4 : 5)]
    return L.len
