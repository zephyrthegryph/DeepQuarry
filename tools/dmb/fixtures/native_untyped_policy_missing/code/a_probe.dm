/datum/probe
    var/entity
    var/call_result
    var/ordered
    var/grouped
    var/raw_value
    proc/test(datum/probe/P)
        entity = P
        call_result = get_entity()
        ordered = /datum/allowed
        grouped = /datum/rejected
        raw_value = get_entity()
/proc/get_entity()
    return new /datum/allowed
SCHEMA(/datum/probe, ordered, schema_path(/datum/rejected))
SCHEMA(/datum/probe, grouped, schema_path(/datum/rejected))
