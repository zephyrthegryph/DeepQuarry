/datum/empty_only
    var/list/empty[]
/datum/empty_only/child
/datum/shared_only
    var/static/list/shared[]
/datum/explicit_only
    var/list/explicit[] = list(7)
var/list/global_empty[]
/proc/work(list/hint[])
    var/static/list/local_empty[]
    return local_empty