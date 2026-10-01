var/global/native_global_probe = 17
/world/New()
    ..()
    var/result = global.vars["native_global_probe"]
    world.log << "GLOBAL_VARS [result]"
    del(world)
