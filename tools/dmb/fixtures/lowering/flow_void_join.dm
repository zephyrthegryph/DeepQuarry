/proc/flow_assertion(flag)
    ASSERT(flag)
    return 1
/proc/flow_direct_crash()
    CRASH("bad")

/proc/void_value_flick(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = flick("idle", target)
#else
    flick("idle", target)
    var/value = null
#endif
    return value

/proc/void_value_walk2(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = walk(target, NORTH)
#else
    walk(target, NORTH)
    var/value = null
#endif
    return value

/proc/void_value_walk3(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = walk(target, NORTH, delay)
#else
    walk(target, NORTH, delay)
    var/value = null
#endif
    return value

/proc/void_value_walk4(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = walk(target, NORTH, delay, 2)
#else
    walk(target, NORTH, delay, 2)
    var/value = null
#endif
    return value

/proc/void_value_walk_to2(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = walk_to(target, target)
#else
    walk_to(target, target)
    var/value = null
#endif
    return value

/proc/void_value_walk_to4(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = walk_to(target, target, 1, delay)
#else
    walk_to(target, target, 1, delay)
    var/value = null
#endif
    return value

/proc/void_value_walk_to5(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = walk_to(target, target, 1, delay, 2)
#else
    walk_to(target, target, 1, delay, 2)
    var/value = null
#endif
    return value

/proc/void_value_walk_towards2(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = walk_towards(target, target)
#else
    walk_towards(target, target)
    var/value = null
#endif
    return value

/proc/void_value_walk_towards3(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = walk_towards(target, target, delay)
#else
    walk_towards(target, target, delay)
    var/value = null
#endif
    return value

/proc/void_value_walk_towards4(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = walk_towards(target, target, delay, 2)
#else
    walk_towards(target, target, delay, 2)
    var/value = null
#endif
    return value

/proc/void_value_walk_away3(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = walk_away(target, target, 1)
#else
    walk_away(target, target, 1)
    var/value = null
#endif
    return value

/proc/void_value_walk_away4(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = walk_away(target, target, 1, delay)
#else
    walk_away(target, target, 1, delay)
    var/value = null
#endif
    return value

/proc/void_value_walk_away5(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = walk_away(target, target, 1, delay, 2)
#else
    walk_away(target, target, 1, delay, 2)
    var/value = null
#endif
    return value

/proc/void_value_walk_rand2(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = walk_rand(target, delay)
#else
    walk_rand(target, delay)
    var/value = null
#endif
    return value

/proc/void_value_walk_rand3(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = walk_rand(target, delay, 2)
#else
    walk_rand(target, delay, 2)
    var/value = null
#endif
    return value

/proc/void_value_winset(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = winset(player, "pane", "is-visible=false")
#else
    winset(player, "pane", "is-visible=false")
    var/value = null
#endif
    return value

/proc/void_value_winshow(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = winshow(player, "pane", 1)
#else
    winshow(player, "pane", 1)
    var/value = null
#endif
    return value

/proc/void_value_winclone(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = winclone(player, "pane", "copy")
#else
    winclone(player, "pane", "copy")
    var/value = null
#endif
    return value

/proc/void_value_sleep(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = sleep(delay)
#else
    sleep(delay)
    var/value = null
#endif
    return value

/proc/void_value_rand_seed(atom/movable/target, client/player, delay)
#ifdef OPENDREAM
    var/value = rand_seed(42)
#else
    rand_seed(42)
    var/value = null
#endif
    return value

/proc/void_conditional_sleep(flag, delay)
#ifdef OPENDREAM
    (flag ? 5 : sleep(delay))
#else
    if(!flag)
        sleep(delay)
#endif
    return 1

/proc/void_argument_sleep(delay)
#ifdef OPENDREAM
    return void_echo(sleep(delay))
#else
    sleep(delay)
    return void_echo(null)
#endif
/proc/void_echo(value)
    return value
