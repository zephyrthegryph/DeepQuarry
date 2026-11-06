/datum/global_probe_value
    var/present
var/datum/global_probe_value/shared_probe
/datum/global_probe_owner
    var/only_field
/datum/global_probe_owner/proc/probe(only_local)
    var/shared_probe = 2
    var/positive = ::shared_probe.present
    var/builtin = ::world.name
    var/first = ::only_local
    var/second = missing_unscoped
    var/third = ::only_field
    var/fourth = ::shared_probe.absent_field
