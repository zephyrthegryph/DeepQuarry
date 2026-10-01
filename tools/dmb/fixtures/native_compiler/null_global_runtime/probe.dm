var/global/datum/shared_base/child/GLOB
/datum/shared_base
    var/static/shared = 7
/datum/shared_base/child
/proc/read_null()
    return GLOB.shared
/proc/write_null(value)
    GLOB.shared = value
/proc/read_safe(datum/shared_base/child/x)
    return x?.shared
/proc/write_safe(datum/shared_base/child/x, value)
    x?.shared = value
/world/New()
    var/before = read_null()
    write_null(9)
    write_safe(null, 100)
    var/safe_null = isnull(read_safe(null))
    var/datum/shared_base/child/x = new
    write_safe(x, 11)
    world.log << "NULL_GLOBAL [before] [safe_null] [read_safe(x)] [read_null()]"
    del(world)
