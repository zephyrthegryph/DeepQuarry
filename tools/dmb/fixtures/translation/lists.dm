/world/New()
    ..()
    var/list/items = list(4, 5, 6)
    items += 7
    var/list/lookup = list("answer" = 42)
    world.log << "LISTS [items.len] [items[2]] [lookup["answer"]]"
