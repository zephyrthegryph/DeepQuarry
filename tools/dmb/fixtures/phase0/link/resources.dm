var/resource_z = 'alias_z.txt'
/datum/resource_order
    var/resource_a = 'alias_a.txt'
    proc/resource_method()
        return 'alias_m.txt'
/world/New()
    ..()
    var/datum/resource_order/R = new
    phase0_emit("global_alias", "[resource_z]")
    phase0_emit("field_alias", "[R.resource_a]")
    phase0_emit("proc_alias", "[R.resource_method()]")
    phase0_emit("alias_equal", resource_z == R.resource_a)
    phase0_finish()
