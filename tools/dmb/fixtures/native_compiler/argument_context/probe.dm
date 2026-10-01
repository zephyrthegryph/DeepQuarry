var/global/default_global = 3
/datum/context_base
    var/seed = 5
    var/list/options = list(10,20)
    var/static/default_static = 7
    proc/defaults(a = seed, b = a + default_global, c = default_static)
        return a*100+b*10+c
    proc/choices(value in src.options)
        return value
    proc/bare_choices(value in options)
        return value
/datum/context_base/child
    seed = 8
    defaults(a = seed, b = a + default_global, c = default_static)
        return ..(a,b,c)+1
/world/New()
    ..()
    var/datum/context_base/B = new
    var/datum/context_base/child/C = new
    world.log << "CONTEXT_DEFAULTS [B.defaults()] [B.defaults(b=4)] [B.defaults(a=2)] [C.defaults()] [C.defaults(a=2)]"
    world.log << "CONTEXT_SOURCE [B.choices(12)] [B.bare_choices(13)]"
    del(world)
