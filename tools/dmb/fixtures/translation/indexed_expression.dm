var/global/list/ie_trace = list()
/proc/ie_value()
    ie_trace += "value"
    return 7
/proc/ie_list()
    ie_trace += "list"
    return ie_trace
/proc/ie_key()
    ie_trace += "key"
    return 1
/proc/ie_effect()
    return ie_list()[ie_key()] = ie_value()
/proc/ie_chain(var/list/L,k,x)
    var/answer = L[k] = x+1
    return answer
/proc/ie_cond(var/list/L,k,a,x,y)
    return L[k] = a ? x+1 : y*2