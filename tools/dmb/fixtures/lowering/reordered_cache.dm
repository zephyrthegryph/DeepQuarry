/world
/datum/reordered_cache
    var/value = 1
    proc/owner()
        return src
    proc/prompt_before()
        var/b = input(world.time + value, world.time, world.time) as anything in list(world.time)
        return world.time + b
    proc/prompt_after()
        var/b = input(value + world.time, world.time, world.time + value) as anything in list(world.time)
        return world.time + b
    proc/prompt_conditional(flag)
        var/b = input(flag ? value : world.time, world.time, flag ? world.time : value) as anything in list(world.time)
        return world.time + b
    proc/prompt_getter(flag)
        var/b = input(owner().value + world.time, world.time, flag ? value : world.time) as anything in list(world.time)
        return world.time + b
    proc/range_world()
        var/b = ((world.time + value) in (world.time) to (world.time))
        return world.time + b
    proc/range_conditional(flag)
        var/b = ((flag ? world.time : value) in (world.time) to (flag ? value : world.time))
        return world.time + b
    proc/pick_world_weights()
        var/b = pick(world.time; value + world.time, world.time; world.time + value)
        return world.time + b
    proc/pick_world_literals()
        var/b = pick(1; world.time + value, 2; value + world.time)
        return world.time + b
