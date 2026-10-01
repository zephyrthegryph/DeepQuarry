/proc/flow_indexed_join_loops(list/left, list/right, mode)
    for(var/a as anything in right)
        for(var/b as anything in right)
            left[b] += mode ? 1 : 2
    return left
