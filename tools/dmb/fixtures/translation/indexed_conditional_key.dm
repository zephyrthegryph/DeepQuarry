/proc/indexed_conditional_key(list/L, condition, first, second, value)
    L[condition ? first : second] += value
