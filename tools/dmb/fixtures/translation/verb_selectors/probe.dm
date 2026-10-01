/proc/before(datum/dispatch/D)
    return D.action()
/datum/dispatch/verb/action()
    set name="renamed action"
    return 1
/datum/dispatch/proc/self_call()
    return action()
/datum/dispatch/proc/proc_alias()
    set name="same display"
    return 3
/datum/dispatch/verb/verb_alias()
    set name="same display"
    return 4
/datum/child
    parent_type=/datum/dispatch
/datum/child/action()
    return 2
/proc/after(datum/dispatch/D)
    return D.action()
/proc/after_arglist(datum/dispatch/D,list/A)
    return D.action(arglist(A))
/proc/after_safe(datum/dispatch/D)
    return D?.action()
/proc/dynamic(D)
    return D:action()
/proc/collision_verb(datum/dispatch/D)
    return D.verb_alias()
/proc/collision_proc(datum/dispatch/D)
    return D.proc_alias()
/datum/child/proc/inherited_self()
    return action()
/proc/get_dispatch(datum/dispatch/D)
    return D
/proc/computed(datum/dispatch/D)
    return get_dispatch(D).action()
/proc/conditional(flag,datum/dispatch/D,datum/dispatch/E)
    return (flag ? D : E).action()
/proc/safe_arglist(datum/dispatch/D,list/A)
    return D?.action(arglist(A))
/proc/statement(datum/dispatch/D)
    D.action()
    return 5
/proc/explicit_proc(datum/dispatch/D)
    return D.proc_alias()
/datum/dispatch/verb/static_action()
    set name="static action"
    var/obj/O=new
    return O
/proc/static_verb(datum/dispatch/D)
    return D.static_action()
/proc/static_verb_safe(datum/dispatch/D)
    return D?.static_action()
/proc/static_verb_arglist(datum/dispatch/D,list/A)
    return D.static_action(arglist(A))
/proc/static_verb_statement(datum/dispatch/D)
    D.static_action()
    return 8
