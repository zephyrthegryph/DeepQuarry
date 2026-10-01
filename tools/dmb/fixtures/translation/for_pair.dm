/obj/proc/pairs(list/L)
    var/list/out = list()
    for(var/key,value in L)
        out += "[key]=[value]"
    return out
/obj/proc/named(list/L)
    var/list/out = list()
    for(var/state,name in L)
        out += "[state]=[name]"
    return out
