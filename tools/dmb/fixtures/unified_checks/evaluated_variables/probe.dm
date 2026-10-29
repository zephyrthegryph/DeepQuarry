var/datum/target/root_target
/datum/target
    var/datum/target/next
    var/list/datum/target/members
/datum/probe
    var/datum/target/owned
/datum/probe/proc/inspect(datum/target/typed, list/datum/target/typed_list, plain)
    typed.absent_parameter
    typed.next.absent_nested
    typed_list[1].absent_list_parameter
    var/datum/target/local = typed
    local.absent_local
    var/list/datum/target/items = list()
    items[1].absent_list_local
    owned.absent_owned
    root_target.absent_root
    global.root_target.absent_explicit_root
    missing_unscoped
    global.missing_global
