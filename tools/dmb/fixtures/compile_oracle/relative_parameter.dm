/world
    name = "Relative typed parameter oracle"
/datum/marker_target
    var/value = 7
/proc/relative_parameter(datum/marker_target/target)
    return target.value
