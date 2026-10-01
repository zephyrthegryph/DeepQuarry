/world/proc/managed()
    return list(1)
/proc/read_name()
    world.managed()
    return world.name
/proc/read_contents()
    world.managed()
    return world.contents
/proc/read_global()
    world.managed()
    helper()
    return world.name
/proc/write_name()
    world.managed()
    world.name="x"
    return world.name
/proc/compound_name()
    world.managed()
    world.name+="x"
    return world.name
/proc/other_owner(datum/holder/O)
    world.managed()
    O.managed()
    return world.name
/proc/read_branch(flag)
    world.managed()
    if(flag)
        return world.name
    return world.name
/proc/helper()
    return list(2)
/datum/holder/proc/managed()
    return list(3)
