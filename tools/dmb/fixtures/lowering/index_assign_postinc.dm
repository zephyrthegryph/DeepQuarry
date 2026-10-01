/proc/index_assign_postinc(var/list/result,var/list/R,var/i)
    result[result.len] = R[i++]
    return result