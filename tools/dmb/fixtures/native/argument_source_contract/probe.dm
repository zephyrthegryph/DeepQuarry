var/global/source_frame_calls = 0

/proc/observe_frame(label, first, count, first_argument)
    source_frame_calls++
    world.log << "DQ_ARGFRAME helper [label] first=[first] count=[count] arg1=[first_argument]"
    return list(first)

/proc/earlier(first, value in observe_frame("earlier", first, args.len, args[1]))
    return value

/proc/argument_count(first, value in list(args.len))
    return value

/proc/argument_first(first, value in list(args[1]))
    return value

/world/New()
    ..()
    world.log << "DQ_ARGFRAME earlier [earlier(7, 7)]"
    world.log << "DQ_ARGFRAME count [argument_count(7, 2)]"
    world.log << "DQ_ARGFRAME first [argument_first(7, 7)]"
    world.log << "DQ_ARGFRAME calls [source_frame_calls]"
    world.log << "DQ_ARGFRAME finished"
    shutdown()
