/obj/box/proc/reference_target(plain)
    return plain
/obj/box/proc/reference_arguments()
    src::reference_target(
        plain = 2
    )
    src::reference_target(
        list(
            plain = 3
        )
    )
    list(
        plain = 4
    )
    ::global_target(
        plain = 5
    )
    ::global_target(list(
        plain = 6
    ))
    var/Target = /obj/box
    new Target(
        plain = 7
    )
    new src.type(list(
        plain = 8
    ))
    new /obj/box{
        plain = list(
            plain = 9
        )
    }(
        plain = 10
    )
    /obj/box{
        plain = list(
            plain = 11
        )
    }
/proc/global_target(value)
    return value
