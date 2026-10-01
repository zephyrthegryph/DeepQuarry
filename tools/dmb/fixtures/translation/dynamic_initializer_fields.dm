#define GEN_NUM "num"

/datum/dynamic_initializer_probe
    var/list/items = list("declaration")
    items = list("first override")
    items = list("second override")

    var/list/cleared = list("declaration")
    cleared = null

    var/datum/created
    created = new /datum

    var/plain = 3
    plain = 4

/particles/dynamic_initializer_probe
    drift = generator(GEN_NUM, 0, 1)
