/var/dynamic_path
/proc/detect_dynamic_path()
    return "x"
/proc/call_dynamic_owner()
    return call_ext((dynamic_path || detect_dynamic_path()), "run")()
/proc/call_dynamic_owner_args(var/a, var/b)
    return call_ext((dynamic_path || detect_dynamic_path()), "run")(a,b)
/proc/call_dynamic_owner_encoded(var/a)
    return call_ext((dynamic_path || detect_dynamic_path()), "run")(json_encode(a))
