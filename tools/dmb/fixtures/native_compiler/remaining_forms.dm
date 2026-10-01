/proc/iterator_anything(list/L)
    var/result = 0
    for(var/datum/D as anything in L)
        result += 1
    return result
/proc/iterator_union(list/L)
    var/result = 0
    for(var/atom/movable/A as mob|obj in L)
        result += 1
    return result
/proc/iterator_turf(list/L)
    var/result = 0
    for(var/turf/T in L)
        result += 1
    return result
/proc/sqlite_arg(database/sqlite_object)
    return sqlite_object
/proc/sqlite_arg_query(database/query/Q)
    return Q
/proc/sqlite_local()
    var/database/db = new("data/test.db")
    return db
/proc/sqlite_query_local()
    var/database/query/Q = new("SELECT 1")
    return Q
/datum/sqlite_probe
    var/database/db
/datum/sqlite_probe/proc/assign_db()
    db = new("data/test.db")
    return db
