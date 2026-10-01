/proc/wc_value(x)
    return x
/proc/wc_in_or(a,b,c)
    return wc_value(a) in wc_value(b) || wc_value(c)
/proc/wc_in_ternary(a,b,c,d)
    return wc_value(a) in wc_value(b) ? wc_value(c) : wc_value(d)
/proc/wc_explicit_or(a,b,c)
    return (wc_value(a) in wc_value(b)) || wc_value(c)
/proc/wc_explicit_ternary(a,b,c,d)
    return (wc_value(a) in wc_value(b)) ? wc_value(c) : wc_value(d)
/proc/wc_named_usr(usr)
    return usr
