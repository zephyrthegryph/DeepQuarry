/world
    name = "Absolute typed parameter oracle"
/datum/marker_target
    var/value = 7
/proc/absolute_parameter(/datum/marker_target/target)
    return target.value
