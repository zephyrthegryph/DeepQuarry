/datum/identity_base
    var/value = 0
    var/observed = 0
    New()
        ..()
        observed = value
/datum/identity_base/child

/world/New()
    ..()
    var/datum/identity_base/D = new /datum/identity_base{value=11}
    var/datum/identity_base/child/C = new /datum/identity_base/child{value=12}
    var/list/T = typesof(/datum/identity_base)
    world.log << "MOD_ID base=[D.type] base_parent=[D.parent_type] child=[C.type] child_parent=[C.parent_type]"
    world.log << "MOD_CHECK observed=[D.observed] child_observed=[C.observed] base_istype=[istype(D,/datum/identity_base)] child_istype=[istype(C,/datum/identity_base/child)] cross_istype=[istype(D,/datum/identity_base/child)]"
    world.log << "MOD_TYPES size=[T.len] contains_base=[(/datum/identity_base in T)] contains_child=[(/datum/identity_base/child in T)] contains_modified_base=[(D.type in T)] contains_modified_child=[(C.type in T)]"
    del(world)
