/datum/fixture_parent
    var/value = 5
    proc/result()
        return value

/datum/fixture_parent/fixture_child
    value = 9
    result()
        return ..() + 1

/world/New()
    ..()
    var/datum/fixture_parent/fixture_child/child = new
    world.log << "INHERITANCE [child.result()]"
