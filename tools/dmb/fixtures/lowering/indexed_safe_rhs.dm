/proc/indexed_safe_append(L, key, owner)
    L[key] += get_step(owner, 0)?.z || 0
/proc/indexed_safe_remove(L, key, owner)
    L[key] -= get_step(owner, 0)?.z || 0
