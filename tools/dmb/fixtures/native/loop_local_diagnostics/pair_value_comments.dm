/proc/probe()
    var/value = 1
    for(var/key, value in list("a" = 2))
        // A comment between the header and its first body token.
        /* A second comment. */
        return value
