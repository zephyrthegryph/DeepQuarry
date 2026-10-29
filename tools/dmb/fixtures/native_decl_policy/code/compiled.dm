/obj/probe/Initialize()
    create_reagents(10)
    air_contents = new /datum
    registry_join(src)
    GLOB.probe_service.register(src)
    connect_to_network()
    after(src, 1, null)
    icon_state = "probe"
    own_set(src, "child", new /obj)
/obj/probe/on_materialize()
    registry_join(src)
    GLOB.probe_service.register(src)
    after(src, 1, null)
    icon_state = "not_a_materialize_rule"
/obj/probe/on_destroy()
    qdel(dead_owned)
    dump_contents()
    registry_leave(src)
    STOP_PROCESSING(probe, src)
    disconnect_from_network()
    visible_message("destroyed")
/obj/kept/Initialize()
    create_reagents(10) // ALLOW(decl): fixture intentionally preserves this lifecycle reagent allocation
/datum/manual/proc/Initialize()
    after(src, 1, null)
/datum/alias
    parent_type = /obj
    Initialize()
        after(src, 1, null)
#define MAKE_HOOK /obj/macro/Initialize()
MAKE_HOOK
    create_reagents(10)
/obj/nested
    Initialize()
        create_reagents(10)
#if 0
/obj/not_compiled/Initialize()
    create_reagents(10)
#endif
