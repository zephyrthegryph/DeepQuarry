/proc/statement(list/x,i,y)
    x[i] ||= y
    return x[i]
/proc/expression(list/x,i,y)
    return (x[i] ||= y)
/proc/simple_expression(x,y)
    return (x ||= y)
