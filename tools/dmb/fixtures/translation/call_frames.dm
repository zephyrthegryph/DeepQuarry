/proc/frame_callee()
    set name = "Frame Callee"
    set desc = "callee description"
    return callee
/proc/frame_caller()
    return caller
/proc/frame_names()
    return list(callee.name, callee.desc, caller.name)
/proc/frame_arguments(value=5)
    callee.args[1] = 7
    return callee.args[1]
/proc/frame_alias()
    var/callee/current = callee
    return current.caller
/proc/frame_type()
    return /callee
/proc/frame_alist_type()
    return /alist
/proc/frame_builtin_types()
    return list(/alist,/callee,/vector,/icon,/sound,/database,/database/query,/regex,/matrix,/generator)
