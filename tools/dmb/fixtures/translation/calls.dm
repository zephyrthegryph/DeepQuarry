/proc/fixture_double(value)
    return value * 2

/datum/fixture_math/proc/sum(a, b)
    return a + b

/world/New()
    ..()
    var/datum/fixture_math/math = new
    world.log << "CALLS [fixture_double(4)] [math.sum(3, 5)]"
