/proc/client_iterator()
    for(var/client/C)
        return C
/proc/dynamic_initial(obj/O, obj/K)
    return initial(O.vars[K.name])
