// Minimal compiler semantics controls; no game or FFI dependency.
/var/const/callable_fixture_resource = 'contract-resource.txt'
/datum/callable_receiver
    var/marker = 23
/datum/callable_receiver/verb/member_only()
    return marker
/datum/callable_receiver/proc/self_verb()
    return member_only()
/proc/typed_copy(list/value)
    return value.Copy()
/proc/safe_copy(value)
    return value?.Copy()
/proc/dynamic_verb(value)
    return value:member_only()
/proc/typed_verb(datum/callable_receiver/value)
    return value.member_only()
/proc/catch_number()
    try
        throw 41
    catch(var/caught)
        return caught + 1
/proc/catch_exception()
    try
        throw new /exception("caught")
    catch(var/exception/caught)
        return istype(caught, /exception)
/proc/explicit_array_methods()
    var/list/value[2] = list(7)
    value.Add(11)
    var/list/copied = value.Copy()
    return copied[1] + copied[2]
/proc/implicit_array_methods()
    var/value[2]
    value.Add(13)
    var/list/copied = value.Copy()
    return length(copied) + copied[3]
/datum/callable_field_array
    var/items[2]
/datum/callable_field_array/proc/field_array_methods()
    items.Add(7)
    var/list/copied = items.Copy()
    return length(copied) + copied[3]
/proc/for_list_methods()
    for(var/list/value = list(7); value; value = null)
        value.Add(11)
        return value.Copy()[1] + value.Copy()[2]
    return 0
/proc/for_source_receiver()
    for(var/datum/callable_receiver/value = new; value; value = null)
        return value.member_only()
    return 0
/world/New()
    ..()
    world.log << file2text(callable_fixture_resource)
    var/list/original = list(7, 11)
    var/list/copied = typed_copy(original)
    copied[1] = 99
    world.log << "DQ_CALL copy_length [length(copied)]"
    world.log << "DQ_CALL copy_value [copied[1]]"
    world.log << "DQ_CALL original_value [original[1]]"
    var/list/safe = safe_copy(original)
    world.log << "DQ_CALL safe_known [safe[2]]"
    world.log << "DQ_CALL safe_null [isnull(safe_copy(null))]"
    var/datum/callable_receiver/receiver = new
    world.log << "DQ_CALL colon_verb [dynamic_verb(receiver)]"
    world.log << "DQ_CALL typed_verb [typed_verb(receiver)]"
    world.log << "DQ_CALL self_verb [receiver.self_verb()]"
    world.log << "DQ_CALL catch_number [catch_number()]"
    world.log << "DQ_CALL catch_exception [catch_exception()]"
    world.log << "DQ_CALL explicit_array_methods [explicit_array_methods()]"
    world.log << "DQ_CALL implicit_array_methods [implicit_array_methods()]"
    var/datum/callable_field_array/field_receiver = new
    world.log << "DQ_CALL field_array_methods [field_receiver.field_array_methods()]"
    world.log << "DQ_CALL for_list_methods [for_list_methods()]"
    world.log << "DQ_CALL for_source_receiver [for_source_receiver()]"
    world.log << "DQ_CALL finished"
    shutdown()
