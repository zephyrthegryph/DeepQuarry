/obj/trailing_probe
    name = "Trailing Probe"
/var/global/type_with_slash = /obj/trailing_probe/
/var/global/type_without_slash = /obj/trailing_probe
/proc/type_path_with_slash()
    return /obj/trailing_probe/
/proc/type_path_without_slash()
    return /obj/trailing_probe
/proc/new_with_slash()
    return new /obj/trailing_probe/()
/proc/new_without_slash()
    return new /obj/trailing_probe()
