var/global/fixture_global = 2

/datum/fixture_counter
    var/member = 3
    proc/advance()
        var/static/calls = 0
        calls += 1
        return member + calls

/world/New()
    ..()
    var/datum/fixture_counter/counter = new
    world.log << "VARIABLES [fixture_global] [counter.advance()] [counter.advance()]"
