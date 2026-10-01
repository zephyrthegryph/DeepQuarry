/datum/static_one
    var/const/limit = 3
    var/static/count = 1
    var/static/list/cache = list(limit, count)
    proc/increment()
        count += 1
        return count
/datum/static_one/child
    var/static/list/child_cache = list(cache)
/datum/static_two
    var/static/count = 7
    var/static/list/cache = list(count)
