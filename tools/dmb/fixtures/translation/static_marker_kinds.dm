var/global/list/global_list = list(1)
var/global/global_number = rand(1, 2)

/datum/marker_scope
    var/list/items = list(1)
    items = list(2)

/proc/static_marker_probe()
    var/static/list/proc_list = list(1)
    var/static/proc_number = rand(1, 2)
    var/static/image/proc_image = image(/obj)
    var/static/icon/proc_icon = icon()
    return proc_list
