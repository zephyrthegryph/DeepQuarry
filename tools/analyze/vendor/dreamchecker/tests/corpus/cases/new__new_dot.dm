/mob/subtype
/mob/proc/foo()
/mob/proc/test()
    . = /mob
    var/list/L = list()
    new .
    new()
    new /obj()
    new /obj{name = "foo"}()
    new .subtype()
    new src.name
    new foo()()
    new /obj[0]() // TODO: see parser.rs
    new 2 + 2() // TODO: see parser.rs
