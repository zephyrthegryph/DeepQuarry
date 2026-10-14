/datum/probe
    var/list/plain
    var/list/empty[]
    var/list/zero[0]
    var/list/sized[2]
    var/list/explicit[] = list(7)
    var/static/list/shared[]
    proc/work(list/hint[])
        var/static/list/local_shared[]
        return local_shared