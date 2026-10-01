/client/tagged
/proc/cp_base()
    return /client
/proc/cp_child()
    return /client/tagged
/proc/cp_loop()
    for(var/client/tagged/C)
        return C