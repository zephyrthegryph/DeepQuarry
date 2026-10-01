var/global/datum/controller/GLOB
var/global/observed_map
/datum/controller
    var/value = 7
    New()
        GLOB = src
/world/proc/Genesis()
    new /datum/controller
/area/proof/New()
    observed_map = GLOB.value
/world
    area = /area/proof
    maxx = 1
    maxy = 1
    maxz = 1
/world/New()
    world.log << "GENESIS_MAP [GLOB.value] [observed_map]"
    del(world)
