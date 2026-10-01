/var/function_path
/proc/call_path(var/a,var/b)
    return call_ext(function_path)(a,b)
/proc/call_path_arglist(...)
    return call_ext(function_path)(arglist(args))
/proc/call_plain_path(var/a,var/b)
    return call(function_path)(a,b)
