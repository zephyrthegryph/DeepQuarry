/proc/mc_item(a, x, y, var/list/L)
    return (a ? x : y) in L
/proc/mc_list(a, x, var/list/L, var/list/M)
    return x in (a ? L : M)
/proc/mc_both(a,b,x,y,var/list/L,var/list/M)
    return (a ? x : y) in (b ? L : M)
/proc/mc_value(x)
    return x
/proc/mc_nested(a,b,x,y,var/list/L,var/list/M)
    return mc_value(a ? (b ? x : y) : x+1) in mc_value(a ? L : M)
/proc/mc_branch(a,x,y,var/list/L)
    if((a ? x : y) in L)
        return 1
    return 0