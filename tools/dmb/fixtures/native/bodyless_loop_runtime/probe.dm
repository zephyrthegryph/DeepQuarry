/proc/each_empty_dedented()
    for(var/value as anything in list())
    return 9

/proc/each_empty_braces()
    for(var/value as anything in list()) {}
    return 9

/proc/each_empty_semicolon()
    for(var/value as anything in list());
    return 9

/proc/each_nonempty_dedented()
    for(var/value as anything in list(2))
    return 9

/proc/each_nonempty_braces()
    for(var/value as anything in list(2)) {}
    return 9

/proc/each_nonempty_semicolon()
    for(var/value as anything in list(2));
    return 9

/proc/pair_empty_dedented()
    for(var/key, value in list())
    return 9

/proc/pair_empty_braces()
    for(var/key, value in list()) {}
    return 9

/proc/pair_empty_semicolon()
    for(var/key, value in list());
    return 9

/proc/pair_nonempty_dedented()
    for(var/key, value in list("a" = 2))
    return 9

/proc/pair_nonempty_braces()
    for(var/key, value in list("a" = 2)) {}
    return 9

/proc/pair_nonempty_semicolon()
    for(var/key, value in list("a" = 2));
    return 9

/world/New()
    ..()

    observe("each_empty_dedented", each_empty_dedented())

    observe("each_empty_braces", each_empty_braces())

    observe("each_empty_semicolon", each_empty_semicolon())

    observe("each_empty_include_return", each_empty_include_return())

    observe("each_nonempty_dedented", each_nonempty_dedented())

    observe("each_nonempty_braces", each_nonempty_braces())

    observe("each_nonempty_semicolon", each_nonempty_semicolon())

    observe("each_nonempty_include_return", each_nonempty_include_return())

    observe("pair_empty_dedented", pair_empty_dedented())

    observe("pair_empty_braces", pair_empty_braces())

    observe("pair_empty_semicolon", pair_empty_semicolon())

    observe("pair_empty_include_return", pair_empty_include_return())

    observe("pair_nonempty_dedented", pair_nonempty_dedented())

    observe("pair_nonempty_braces", pair_nonempty_braces())

    observe("pair_nonempty_semicolon", pair_nonempty_semicolon())

    observe("pair_nonempty_include_return", pair_nonempty_include_return())

    world.log << "DQ_BODYLESS finished"
    shutdown()

/proc/observe(label, value)
    world.log << "DQ_BODYLESS [label] null=[isnull(value)] value=[value]"
