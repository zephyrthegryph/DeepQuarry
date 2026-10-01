/var/const/global_limit = 9
/datum/local_scope
    var/const/limit = 30
    proc/read()
        var/const/limit = 3
        var/const/copy = limit + 1
        var/static/list/cache = list(limit, copy)
        var/static/slots[2]
        return cache
/proc/other()
    var/const/limit = 7
    var/static/list/cache = list(limit)
    return cache
/var/const/positive_infinity = 1.#INF
/var/const/negative_infinity = -1.#INF
