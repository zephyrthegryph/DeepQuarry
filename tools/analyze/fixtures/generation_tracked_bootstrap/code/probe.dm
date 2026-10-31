#define TRACKED(T, v)
/datum/base
    var/list/entries = list()
TRACKED(/datum/base, entries)
TRACKED(/datum/base, entries)
/datum/child
    parent_type = /datum/base
    entries = null
TRACKED(/datum/child, entries)
/datum/init
    var/value = list()
    var/list/cells[2][3]
    var/text/title
TRACKED(/datum/init, value)
TRACKED(/datum/init, cells)
TRACKED(/datum/init, title)
/datum/version
    var/list/records
    var/records_version = 1
TRACKED(/datum/version, records)
/datum/collision
    var/list/keys
TRACKED(/datum/collision, keys)
/datum/collision/child/proc/add_keys(x)
    return x
/datum/modded
    var/static/list/cache
TRACKED(/datum/modded, cache)
TRACKED(/mob, contents)
TRACKED(/datum/absent, nonexistent)
/datum/previous
    proc/add_rope(x)
        return x
/datum/next
    var/list/rope
TRACKED(/datum/next, rope)
TRACKED(/datum/test_box, test_items)
/proc/final_tail()
    return
