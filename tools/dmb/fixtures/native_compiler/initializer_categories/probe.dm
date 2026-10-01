/world/proc/Genesis()
    return 0
/world/proc/_()
    var/static/genesis = world.Genesis()
/proc/cache_values()
    var/static/list/list_literal = list(7)
    var/static/list/list_sized = new /list(2)
    var/static/list/list_array[2]
    var/static/alist/alist_literal = alist(1 = 2)
    var/static/list/list_combined = list(1) + list(2)
    var/static/list/list_empty = newlist()
    var/static/list/list_call = list(side_effect())
    var/static/datum/holder/object_literal = new
    var/static/list/list_object = list(new /datum/holder)
    var/static/matrix/matrix_literal = matrix()
    var/static/list/type_list = typesof(/datum/holder)
    var/static/regex/regex_literal = regex("p")
    var/static/list/list_math = list(1 + 2)
    var/static/list/list_assoc = list("key" = "value")
/proc/side_effect()
    return 7
/datum/holder


