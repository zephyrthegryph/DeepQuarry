#define DECLARE_LIST var/list/from_macro = list()
/obj
    var/plain = 1
    var/tmp/temporary
    var/static/list/shared = list()
    var/global/world_shared = list()
    var/const/fixed = 1
    var/list/cleared = list()
    cleared = null
/obj/item
    var/list/datum/elements
    var/datum/sized[2]
/datum/holder
    var/list/items = null
    items = list()
    var/grouped = (list())
    var/populated = list(1)
    DECLARE_LIST
/datum/holder/child
    items = null
