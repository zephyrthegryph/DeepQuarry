/proc/debug_indexed_append(rlist, altlist, i)
    rlist[(i % 2) + 1] += altlist[i]
    return rlist
