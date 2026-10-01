/datum/logical_owner
    var/value
    var/other
/proc/logical_or_arg(datum/logical_owner/O, value)
    O.value ||= value
    return O.value
/proc/logical_or_field(datum/logical_owner/O, datum/logical_owner/K)
    O.value ||= K.other
    return O.value
/proc/logical_and_field(datum/logical_owner/O, datum/logical_owner/K)
    O.value &&= K.other
    return O.value
/proc/logical_identity(datum/logical_owner/O)
    return O
/proc/logical_direct_mutation(datum/logical_owner/a, datum/logical_owner/b)
    a.value ||= (a = b)
    return a
/proc/logical_computed_mutation(datum/logical_owner/a, datum/logical_owner/b)
    logical_identity(a).value ||= (a = b)
    return a
/datum/logical_owner
    var/datum/logical_owner/child
/proc/logical_property_mutation(datum/logical_owner/a, datum/logical_owner/b)
    a.child.value ||= (a.child = b)
    return a
/proc/field_expr_arg(datum/logical_owner/a, datum/logical_owner/b)
    return a.value = b
/proc/field_expr_arg_mutate(datum/logical_owner/a, datum/logical_owner/b)
    return a.value = (a = b)
/proc/field_expr_call_mutate(datum/logical_owner/a, datum/logical_owner/b)
    return logical_identity(a).value = (a = b)
/proc/field_expr_both_calls(datum/logical_owner/a, datum/logical_owner/b)
    return logical_identity(a).value = logical_identity(b)

/proc/field_statement_arg_mutate(datum/logical_owner/a, datum/logical_owner/b)
    a.value = (a=b)
    return a
/proc/field_statement_call_mutate(datum/logical_owner/a, datum/logical_owner/b)
    logical_identity(a).value = (a=b)
    return a
