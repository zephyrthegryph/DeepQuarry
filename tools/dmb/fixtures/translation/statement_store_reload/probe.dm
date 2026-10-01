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
/datum/observer
 var/datum/value
/proc/argument_statement(datum/local)
 local=RHS
 return local
/proc/argument_expression(datum/local)
 return(local=RHS)
/proc/global_statement()
 RHS=new /datum/observer
 RHS=new /datum
 return RHS
/proc/global_expression()
 RHS=new /datum/observer
 return(RHS=new /datum)
/proc/field_statement(datum/observer/O)
 O.value=RHS
 return O.value
/proc/field_expression(datum/observer/O)
 return(O.value=RHS)
/datum/observer/proc/src_statement()
 value=RHS
 return value
/datum/observer/proc/src_expression()
 return(value=RHS)
/proc/numeric_statement()
 var/local=0
 local=7
 return local
/proc/numeric_expression()
 var/local=0
 return(local=7)
/proc/world_statement()
 world.name="changed"
 return world.name
/proc/world_expression()
 return(world.name="changed")
