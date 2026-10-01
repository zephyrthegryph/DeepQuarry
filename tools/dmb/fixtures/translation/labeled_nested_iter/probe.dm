/proc/probe(list/L)
    var/count = 0
    outer_loop:
        for(var/i in L)
            for(var/j in L)
                if(j)
                    continue outer_loop
                count++
    return count
/proc/probe_break(list/L)
    var/count = 0
    outer_loop:
        for(var/i in L)
            for(var/j in L)
                if(j)
                    break outer_loop
                count++
    return count
/proc/probe_inline(list/L)
    var/count = 0
    outer_loop:
        for(var/i in L)
            for(var/j in L)
                count += 1
                if(count == 3) break outer_loop
    return count
/proc/probe_while()
    var/count = 0
    while(count < 3)
        count += 1
    return count
/proc/probe_break_smoke()
    var/count = 0
    break_loop:
        for(var/outer in list(1, 2, 3))
            for(var/inner in list(4, 5))
                count += 1
                if(count == 3) break break_loop
    return count
/proc/probe_full()
    var/count = 0
    break_loop:
        for(var/outer in list(1, 2, 3))
            for(var/inner in list(4, 5))
                count += 1
                if(count == 3) break break_loop
    if(count != 3) return FALSE
    count = 0
    var/total = 0
    continue_loop:
        for(var/outer in list(1, 2, 3))
            for(var/inner in list(4, 5))
                count += 1
                total += outer
                if(count > 8) return FALSE
                continue continue_loop
    return count == 3 && total == 6
/proc/probe_eq(a,b)
    return a == b
/proc/probe_ne(a,b)
    return a != b
/proc/probe_gt(a,b)
    return a > b
/proc/probe_while_eq()
    var/count = 0
    while(count == 0)
        count++
    return count
/proc/probe_switch(x)
    switch(x)
        if(1) return 10
        if(2) return 20
        else return 30
/proc/probe_goto(list/L)
    for(var/i in L)
        for(var/j in L)
            goto done
    done:
        return 1
/proc/probe_goto_same_loop(list/L)
    for(var/i in L)
        goto after_step_label
        after_step_label:
            i += 1
    return 1
/proc/probe_try_return()
    try
        return 7
    catch(var/problem)
        return 8
/proc/probe_return_inner(list/L)
    for(var/i in L)
        for(var/j in L)
            return j
    return 0
/proc/probe_newlist()
    return newlist()
/proc/probe_newlist_one()
    return newlist(/datum)
/proc/probe_continue_plain(list/L)
    var/count = 0
    for(var/i in L)
        if(i) continue
        count += 1
    return count
/proc/probe_continue_cstyle()
    var/count = 0
    for(var/i = 0; i < 3; i++)
        if(i == 1) continue
        count += 1
    return count
/proc/probe_break_plain(list/L)
    var/count = 0
    for(var/i in L)
        if(i) break
        count += 1
    return count
