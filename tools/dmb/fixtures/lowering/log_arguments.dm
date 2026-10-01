/var/list/force_516=alist()
/var/log_calls=0
/proc/log_probe(value)
    log_calls++
    return value
/proc/log_natural(value)
    return log(value)
/proc/log_binary(base,value)
    return log(base,value)
/proc/log_effects()
    return log(log_probe(2),log_probe(8))
/proc/log_base_branch(flag,base,value)
    return log(flag ? base : 2,value)
/proc/log_value_branch(flag,base,value)
    return log(base,flag ? value : 8)
/proc/log_both_branch(flag,base,value)
    return log(flag ? base : 2,flag ? value : 8)
/proc/log_shortcircuit(base,value)
    return log(base || log_probe(2),value || log_probe(8))
/proc/log_loop(list/values)
    var/total=0
    for(var/value in values)
        total += log(log_probe(2),value || 8)
    return total
