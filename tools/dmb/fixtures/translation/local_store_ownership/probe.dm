var/global/datum/RHS
var/global/seen
/datum/observer/Del()
    seen=refcount(RHS)
    return ..()
/proc/assignment_return()
    var/datum/local=new /datum/observer
    RHS=new /datum
    return (local=RHS)
/proc/assignment_call()
    var/datum/local=new /datum/observer
    RHS=new /datum
    return refcount((local=RHS))
/proc/assignment_condition()
    var/datum/local=new /datum/observer
    RHS=new /datum
    if((local=RHS) != null)
        return refcount(local)
/proc/assignment_field(datum/observer/O)
    var/datum/local=O
    RHS=new /datum
    return (local=RHS)
/proc/statement_reload()
    var/datum/local=new /datum/observer
    RHS=new /datum
    local=RHS
    return local
/proc/statement_reload_refcount()
    var/datum/local=new /datum/observer
    RHS=new /datum
    local=RHS
    return refcount(local)
