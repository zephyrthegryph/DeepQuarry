// Standalone Phase 0 fixture; no game framework or generated assets required.
/world
    name = "DMB pair access probe"
    maxx = 1
    maxy = 1
    maxz = 1
    fps = 10

/world/New()
    ..()
    if(file2text('static.txt') != "PHASE0_STATIC_RESOURCE\n")
        world.log << "PHASE0_PAIR_PROBE_FAIL static resource"
        shutdown()
        return
    var/icon/generated = icon('probe.png')
    generated.DrawBox("#ff0000", 1, 1, 1, 1)
    var/dynamic_resource = fcopy_rsc(generated)
    if(!dynamic_resource)
        world.log << "PHASE0_PAIR_PROBE_FAIL dynamic resource"
        shutdown()
        return
    world.log << "PHASE0_PAIR_PROBE_DYNAMIC [dynamic_resource]"
    world.log << "PHASE0_PAIR_PROBE_OK"
    shutdown()
