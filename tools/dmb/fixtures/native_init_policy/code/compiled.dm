/obj
    var/init_from_table = FALSE
// ALLOW(init): fixture exercises the legacy missing reason-code refusal
/obj/bare/Initialize()
    . = ..()
    value = 1
    range(1)
    return .
/obj/late/LateInitialize()
    return
/turf/material/on_materialize()
    return
/datum/not_turf
    parent_type = /turf
    on_materialize()
        return
/obj/tablebase
    init_from_table = TRUE
/obj/tablebase/child/Initialize()
    value = 2
/obj/overridden
    init_from_table = TRUE
/obj/overridden/child/Initialize()
    value = 3
// ALLOW(init/INSTANCE_STATE): fixture retains genuine per-instance state for this owner
/obj/kept/Initialize()
    value = 4
    range(1) // ALLOW(init): fixture deliberately preserves this world read during initialization
/obj/core/Initialize()
    core_state = 1
/datum/manual/Initialize()
    manual_state = 1
#define MAKE_INIT /obj/macro/Initialize()
MAKE_INIT
    macro_state = 1
/obj/nested
    Initialize()
        nested_state = 1
#if 0
/obj/not_compiled/Initialize()
    disabled_state = 1
#endif
