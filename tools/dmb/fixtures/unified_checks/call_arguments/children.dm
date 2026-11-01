/datum/argument_base/a/work(alpha,beta)
    return beta
/datum/argument_base/lexical
    parent_type = /datum
    proc/work(alpha,beta)
        return beta
/datum/argument_outside
    parent_type = /datum/argument_base
    work(alpha,beta)
        return beta
