/datum/target
/datum/base/proc/make() as /datum/target
    return null
/datum/base/child/make()
    return null
/proc/make() as /datum/target
    return null
/proc/default_ignored(datum/value = missing_default()) as /datum/target
    return null
/proc/probe(datum/base/child/source)
    make().absent_header
    source.make().absent_inherited_header
    default_ignored().absent_default_header
    get_step(null, 1).absent_builtin
    block(null, null)[1].absent_block_element
