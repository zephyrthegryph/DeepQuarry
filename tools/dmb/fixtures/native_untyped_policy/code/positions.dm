#define DECL_ITEM var/macro_item
/datum/position_probe
    var/item = list(
        1)
    DECL_ITEM
    proc/set_items(datum/position_probe/P)
        item = P
        macro_item = P
