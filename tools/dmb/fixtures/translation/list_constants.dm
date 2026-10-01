var/global/list/fixture_global = list(1, 2, "three" = 3)

/datum/fixture_lists
    var/static/list/shared = list("a", "b")
    var/list/each = list(4, 5)

/world/New()
    ..()
    var/datum/fixture_lists/example = new
    world.log << "LIST CONSTANTS [fixture_global.len] [example.each.len]"
