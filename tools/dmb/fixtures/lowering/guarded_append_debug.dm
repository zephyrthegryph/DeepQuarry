/datum/debug_counter/proc/amount(i)
    return i
/proc/debug_conditional_append(rlist, datum/debug_counter/owner, i)
    rlist[i] += owner ? owner.amount(i) : 0
    return rlist
