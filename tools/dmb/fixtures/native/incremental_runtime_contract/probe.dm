// Standalone compiler contract, with no game boot, assets or FFI.
var/global/runtime_contract_global = 11

/datum/runtime_contract/base
    var/inherited_value = 3

/datum/runtime_contract/base/proc/measure(delta = 4)
    return inherited_value + delta

/datum/runtime_contract/base/child/measure(delta = 5)
    return ..(delta) + 10

// STRUCTURAL_EXTENSION_BEGIN
/datum/runtime_contract/base/child/proc/extra()
    return 0
// STRUCTURAL_EXTENSION_END

/proc/runtime_contract_defaults(left = 7, right = 2)
    return left + right

/proc/runtime_contract_tick()
    var/static/counter = 20
    counter++
    return counter

/world/New()
    ..()
    var/datum/runtime_contract/base/child/probe = new
    world.log << "DQ_CONTRACT inherited [probe.inherited_value]"
    world.log << "DQ_CONTRACT parent_default [probe.measure()]"
    world.log << "DQ_CONTRACT parent_explicit [probe.measure(2)]"
    world.log << "DQ_CONTRACT argument_defaults [runtime_contract_defaults()]"
    world.log << "DQ_CONTRACT global [runtime_contract_global]"
    world.log << "DQ_CONTRACT static_first [runtime_contract_tick()]"
    world.log << "DQ_CONTRACT static_second [runtime_contract_tick()]"
    world.log << "DQ_CONTRACT structural [probe.extra()]"
    world.log << "DQ_CONTRACT finished"
    shutdown()
