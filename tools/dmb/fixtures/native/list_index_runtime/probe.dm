// List access observations. Errors remain uncaught and abort only the callee.
var/global/index_order = ""
var/global/receiver_calls = 0
var/global/index_calls = 0

// Keep the default runtime reporting while independently observing the exact
// engine-issued debug origin. No catch handler hides or resumes the callee.
/world/Error(exception/E)
    world.log << "DQ_INDEX_ORIGIN [E.file]|[E.line]|[E.name]"
    return ..()

/proc/index_receiver(list/values, label)
    receiver_calls++
    index_order += "R"
    world.log << "DQ_RETIRE receiver [label] [receiver_calls]"
    return values

/proc/index_operand(value, label)
    index_calls++
    index_order += "I"
    world.log << "DQ_RETIRE index [label] [index_calls]"
    return value

/proc/index_lookup(list/values, key, label)
    var/result = index_receiver(values, label)[index_operand(key, label)]
    world.log << "DQ_RETIRE result [label] [result]"
    world.log << "DQ_RETIRE completed [label]"

/proc/index_nested(list/outer, list/inner, key, label)
    var/result = index_receiver(outer, "outer")[index_receiver(inner, "inner")[index_operand(key, label)]]
    world.log << "DQ_RETIRE result [label] [result]"
    world.log << "DQ_RETIRE completed [label]"

/proc/index_case(list/values, key, label)
    receiver_calls = 0
    index_calls = 0
    index_order = ""
    world.log << "DQ_RETIRE begin [label]"
    index_lookup(values, key, label)
    world.log << "DQ_RETIRE end [label] [receiver_calls] [index_calls] [index_order]"

/proc/index_nested_case(list/outer, list/inner, key, label)
    receiver_calls = 0
    index_calls = 0
    index_order = ""
    world.log << "DQ_RETIRE begin [label]"
    index_nested(outer, inner, key, label)
    world.log << "DQ_RETIRE end [label] [receiver_calls] [index_calls] [index_order]"

/world/New()
    ..()
    var/list/values = list(10, 20, "key" = 30)
    index_case(values, 1, "numeric_valid")
    index_case(values, 4, "numeric_bounds")
    index_case(values, 0, "numeric_zero")
    index_case(values, 1.5, "numeric_fractional")
    index_case(values, "key", "string_present")
    index_case(values, "missing", "string_absent")
    index_nested_case(list(100, 200), list(2), 1, "nested_valid")
    index_nested_case(list(100, 200), list(4), 1, "nested_outer_bounds")
    index_nested_case(list(100, 200), list(2), 4, "nested_inner_bounds")
    world.log << "DQ_RETIRE finished"
    shutdown()
