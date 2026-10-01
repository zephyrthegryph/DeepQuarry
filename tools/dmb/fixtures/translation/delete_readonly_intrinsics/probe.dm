/obj/proc/delete_intrinsic_world()
    del(world)
    return 7
/obj/proc/delete_intrinsic_caller()
    del(caller)
    return 7
/obj/proc/delete_intrinsic_callee()
    del(callee)
    return 7
/obj/proc/delete_intrinsic_global_vars()
    del(global.vars)
    return 7
/obj/proc/delete_intrinsic_src_type()
    del(src.type)
    return 7
/obj/proc/delete_intrinsic_src()
    del(src)
    return 7
/obj/proc/delete_intrinsic_usr()
    del(usr)
    return 7
/obj/proc/delete_intrinsic_args()
    del(args)
    return 7
var/global/type = 7
/proc/delete_intrinsic_dynamic_type(O)
    del(O:type)
    return 7
/proc/delete_intrinsic_typed_type(datum/O)
    del(O.type)
    return 7
/proc/delete_intrinsic_safe_type(datum/O)
    del(O?.type)
    return 7
/proc/delete_intrinsic_global_type()
    del(global.type)
    return 7
