var/global/source_frame_calls = 0

/proc/observe_frame(label, first, count, first_argument)
    source_frame_calls++
    world.log << "DQ_ARGFRAME helper [label] first=[first] count=[count] arg1=[first_argument]"
    return list(first)

/proc/earlier(first, value in observe_frame("earlier", first, args.len, args[1]))
    return value

/proc/observe_count(first, count, first_argument)
    source_frame_calls++
    world.log << "DQ_ARGFRAME helper count first=[first] count=[count] arg1=[first_argument]"
    return list(count)

/proc/observe_first(first, count, first_argument)
    source_frame_calls++
    world.log << "DQ_ARGFRAME helper first first=[first] count=[count] arg1=[first_argument]"
    return list(first_argument)

/proc/argument_count(first, value in observe_count(first, args.len, args[1]))
    return value

/proc/argument_first(first, value in observe_first(first, args.len, args[1]))
    return value

/proc/first_source(first in observe_frame("first_source", 1, args.len, null))
    return first

/proc/third_source(first = 7 as num, second in observe_frame("second", first, args.len, args[1]), third in observe_frame("third", second, args.len, args[1]))
    return third

/world/New()
    ..()
    world.log << "DQ_ARGFRAME earlier [earlier(7, 7)]"
    world.log << "DQ_ARGFRAME count [argument_count(7, 2)]"
    world.log << "DQ_ARGFRAME first [argument_first(7, 7)]"
    world.log << "DQ_ARGFRAME first_source [first_source(7)]"
    world.log << "DQ_ARGFRAME third_source [third_source(7, 7, 7)]"
    world.log << "DQ_ARGFRAME calls [source_frame_calls]"
    world.log << "DQ_ARGFRAME finished"
    shutdown()
