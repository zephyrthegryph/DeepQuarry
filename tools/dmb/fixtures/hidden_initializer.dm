/world
    name = "Initializer Markers"

var/global/list/global_list = list(1, 2)

/proc/example()
    var/static/list/static_list = list(3, 4)
    var/list/local_list = list(5, 6)
    return static_list + local_list + global_list

/obj
    var/list/member_list = list(7, 8)
    var/number = 3
