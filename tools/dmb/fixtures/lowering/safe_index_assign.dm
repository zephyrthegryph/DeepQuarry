/datum/holder
    var/air
/proc/safe_index_assign(var/list/L,var/i,var/datum/holder/o)
    L[i] = o?.air
